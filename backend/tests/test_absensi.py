from datetime import UTC, datetime, timedelta

from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import create_access_token
from app.models.akun import AksesOutlet, Pengguna, Role
from app.models.ops import Absensi
from tests.conftest import buat_toko_siap_pakai


async def _karyawan_kasir(db: AsyncSession, toko, nama: str = "Budi Kasir") -> dict:
    """Pengguna kedua di toko yang sama dengan peran Kasir; mengembalikan header otorisasinya."""
    role = (await db.execute(select(Role).where(Role.nama == "Kasir", Role.is_system.is_(True)))).scalar_one()
    pengguna = Pengguna(toko_id=toko.toko.id, role_id=role.id, nama=nama, no_hp="081200000099")
    db.add(pengguna)
    await db.flush()
    db.add(AksesOutlet(pengguna_id=pengguna.id, outlet_id=toko.outlet.id))
    await db.commit()
    token = create_access_token(pengguna_id=pengguna.id, toko_id=toko.toko.id, role_id=role.id)
    return {"Authorization": f"Bearer {token}"}


def _hari_ini() -> str:
    return datetime.now(UTC).date().isoformat()


def _rentang_hari_ini() -> dict:
    return {"dari": _hari_ini(), "sampai": _hari_ini()}


async def test_masuk_keluar_dan_status_saya(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Pro")
    h = toko.headers
    assert (await client.get("/absensi/saya", headers=h)).json() == {"aktif": None}

    masuk = await client.post("/absensi/masuk", headers=h, json={"catatan": "Shift pagi"})
    assert masuk.status_code == 201, masuk.text
    assert masuk.json()["jam_keluar"] is None and masuk.json()["durasi_menit"] is None
    assert masuk.json()["pengguna_nama"] == "Penguji"

    saya = (await client.get("/absensi/saya", headers=h)).json()
    assert saya["aktif"]["id"] == masuk.json()["id"]

    ganda = await client.post("/absensi/masuk", headers=h, json={})
    assert ganda.status_code == 409 and ganda.json()["detail"]["kode"] == "sudah_absen_masuk"

    keluar = await client.post("/absensi/keluar", headers=h, json={"catatan": "Selesai"})
    assert keluar.status_code == 200, keluar.text
    assert keluar.json()["jam_keluar"] is not None and keluar.json()["durasi_menit"] == 0
    assert keluar.json()["catatan"] == "Shift pagi | Selesai"
    assert (await client.get("/absensi/saya", headers=h)).json() == {"aktif": None}

    lagi = await client.post("/absensi/keluar", headers=h, json={})
    assert lagi.status_code == 409 and lagi.json()["detail"]["kode"] == "belum_absen_masuk"
    # Setelah keluar boleh masuk lagi (mis. shift kedua di hari yang sama).
    assert (await client.post("/absensi/masuk", headers=h, json={})).status_code == 201


async def test_rekap_menghitung_durasi_dan_hari_per_karyawan(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Pro")
    sekarang = datetime.now(UTC)
    db_session.add_all([
        Absensi(toko_id=toko.toko.id, outlet_id=toko.outlet.id, pengguna_id=toko.pengguna.id,
                jam_masuk=sekarang - timedelta(hours=3), jam_keluar=sekarang - timedelta(hours=1)),
        Absensi(toko_id=toko.toko.id, outlet_id=toko.outlet.id, pengguna_id=toko.pengguna.id,
                jam_masuk=sekarang - timedelta(minutes=30), jam_keluar=None),
    ])
    await db_session.commit()

    r = await client.get("/absensi", headers=toko.headers, params=_rentang_hari_ini())
    assert r.status_code == 200, r.text
    b = r.json()
    assert len(b["item"]) == 2
    rekap = b["rekap"][0]
    assert rekap["pengguna_nama"] == "Penguji"
    assert rekap["total_menit"] == 120  # hanya baris yang sudah keluar
    assert rekap["masih_masuk"] is True
    assert rekap["jumlah_hari"] >= 1
    selesai = [i for i in b["item"] if i["jam_keluar"] is not None][0]
    assert selesai["durasi_menit"] == 120


async def test_kasir_hanya_melihat_absensi_sendiri_owner_melihat_semua(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    owner = await buat_toko_siap_pakai(db_session, nama_paket="Pro")
    header_kasir = await _karyawan_kasir(db_session, owner)
    await client.post("/absensi/masuk", headers=owner.headers, json={})
    await client.post("/absensi/masuk", headers=header_kasir, json={})

    semua = (await client.get("/absensi", headers=owner.headers, params=_rentang_hari_ini())).json()
    assert {r["pengguna_nama"] for r in semua["rekap"]} == {"Penguji", "Budi Kasir"}
    assert len(semua["item"]) == 2

    sendiri = (await client.get("/absensi", headers=header_kasir, params=_rentang_hari_ini())).json()
    assert [r["pengguna_nama"] for r in sendiri["rekap"]] == ["Budi Kasir"]
    assert len(sendiri["item"]) == 1

    # Absensi kasir tidak mengganggu status masuk owner (masing-masing sendiri).
    assert (await client.post("/absensi/keluar", headers=header_kasir, json={})).status_code == 200
    assert (await client.get("/absensi/saya", headers=owner.headers)).json()["aktif"] is not None


async def test_rentang_tanggal_dan_validasi(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Pro")
    lama = datetime.now(UTC) - timedelta(days=10)
    db_session.add(Absensi(toko_id=toko.toko.id, outlet_id=toko.outlet.id, pengguna_id=toko.pengguna.id,
                           jam_masuk=lama, jam_keluar=lama + timedelta(hours=8)))
    await db_session.commit()

    hari_ini = (await client.get("/absensi", headers=toko.headers, params=_rentang_hari_ini())).json()
    assert hari_ini["item"] == []
    luas = (await client.get(
        "/absensi", headers=toko.headers,
        params={"dari": (lama - timedelta(days=1)).date().isoformat(), "sampai": _hari_ini()},
    )).json()
    assert luas["rekap"][0]["total_menit"] == 480

    salah = await client.get("/absensi", headers=toko.headers, params={"dari": "2026-11-13", "sampai": "2026-11-12"})
    assert salah.status_code == 400


async def test_absensi_digate_paket_dan_outlet_toko_lain(client: AsyncClient, db_session: AsyncSession) -> None:
    gratis = await buat_toko_siap_pakai(db_session, nama_paket="Gratis")
    r = await client.post("/absensi/masuk", headers=gratis.headers, json={})
    assert r.status_code == 403 and r.json()["detail"]["fitur"] == "absensi"

    a = await buat_toko_siap_pakai(db_session, nama_paket="Pro")
    b = await buat_toko_siap_pakai(db_session, nama_paket="Pro")
    asing = await client.post("/absensi/masuk", headers=b.headers, json={"outlet_id": str(a.outlet.id)})
    assert asing.status_code == 404
    # catatan terlalu panjang ditolak
    assert (await client.post("/absensi/masuk", headers=b.headers, json={"catatan": "x" * 301})).status_code == 422


async def test_batas_hari_mengikuti_offset_zona_waktu(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Pro")
    # 23:00 UTC tanggal 11 = 06:00 WIB tanggal 12.
    masuk = datetime(2026, 11, 11, 23, 0, tzinfo=UTC)
    db_session.add(Absensi(toko_id=toko.toko.id, outlet_id=toko.outlet.id, pengguna_id=toko.pengguna.id,
                           jam_masuk=masuk, jam_keluar=masuk + timedelta(hours=8)))
    await db_session.commit()

    wib = (await client.get(
        "/absensi", headers=toko.headers, params={"dari": "2026-11-12", "sampai": "2026-11-12", "tz_menit": 420}
    )).json()
    assert len(wib["item"]) == 1 and wib["rekap"][0]["jumlah_hari"] == 1

    utc = (await client.get(
        "/absensi", headers=toko.headers, params={"dari": "2026-11-12", "sampai": "2026-11-12"}
    )).json()
    assert utc["item"] == [], "tanpa offset, batas hari UTC"
    assert (await client.get(
        "/absensi", headers=toko.headers, params={"dari": "2026-11-12", "sampai": "2026-11-12", "tz_menit": 9999}
    )).status_code == 422
