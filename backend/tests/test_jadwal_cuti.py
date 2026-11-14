from datetime import UTC, date, datetime, timedelta

from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import create_access_token
from app.models.akun import AksesOutlet, Pengguna, Role
from tests.conftest import buat_toko_siap_pakai


async def _kasir(db: AsyncSession, toko, nama: str = "Budi Kasir") -> tuple[Pengguna, dict]:
    role = (await db.execute(select(Role).where(Role.nama == "Kasir", Role.is_system.is_(True)))).scalar_one()
    pengguna = Pengguna(toko_id=toko.toko.id, role_id=role.id, nama=nama, no_hp="081200000077")
    db.add(pengguna)
    await db.flush()
    db.add(AksesOutlet(pengguna_id=pengguna.id, outlet_id=toko.outlet.id))
    await db.commit()
    token = create_access_token(pengguna_id=pengguna.id, toko_id=toko.toko.id, role_id=role.id)
    return pengguna, {"Authorization": f"Bearer {token}"}


def _minggu(shift: str = "pagi") -> dict:
    return {"hari": [{"hari": h, "shift": shift} for h in range(1, 8)]}


def _tgl(offset: int) -> str:
    return (date.today() + timedelta(days=offset)).isoformat()


async def test_jadwal_digate_paket(client: AsyncClient, db_session: AsyncSession) -> None:
    for paket in ("Gratis", "Pro"):
        toko = await buat_toko_siap_pakai(db_session, nama_paket=paket)
        r = await client.get("/jadwal", headers=toko.headers)
        assert r.status_code == 403 and r.json()["detail"]["fitur"] == "staff_schedule"
        r = await client.post("/cuti", headers=toko.headers, json={"jenis": "cuti", "tanggal_mulai": _tgl(1), "tanggal_selesai": _tgl(2)})
        assert r.status_code == 403


async def test_pengelola_mengatur_jadwal_dan_kasir_hanya_melihat_sendiri(client: AsyncClient, db_session: AsyncSession) -> None:
    owner = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    budi, h_budi = await _kasir(db_session, owner)

    atur = await client.put(
        f"/jadwal/{budi.id}",
        headers=owner.headers,
        json={"hari": [
            {"hari": 1, "shift": "pagi"},
            {"hari": 2, "shift": "siang", "jam_mulai": "13:30", "jam_selesai": "21:30"},
            {"hari": 7, "shift": "libur"},
        ]},
    )
    assert atur.status_code == 200, atur.text
    hari = {h["hari"]: h for h in atur.json()["hari"]}
    assert (hari[1]["jam_mulai"], hari[1]["jam_selesai"]) == ("07:00", "15:00"), "jam bawaan shift pagi"
    assert (hari[2]["jam_mulai"], hari[2]["jam_selesai"]) == ("13:30", "21:30")
    assert hari[7]["shift"] == "libur" and hari[7]["jam_mulai"] is None

    # Mengubah sebagian hari tidak menghapus hari lain
    await client.put(f"/jadwal/{budi.id}", headers=owner.headers, json={"hari": [{"hari": 1, "shift": "siang"}]})
    semua = (await client.get("/jadwal", headers=owner.headers)).json()
    budi_baris = [k for k in semua if k["pengguna_nama"] == "Budi Kasir"][0]
    assert {h["hari"]: h["shift"] for h in budi_baris["hari"]} == {1: "siang", 2: "siang", 7: "libur"}
    assert {k["pengguna_nama"] for k in semua} == {"Penguji", "Budi Kasir"}

    # Kasir: hanya dirinya, dan tidak boleh mengatur jadwal
    sendiri = (await client.get("/jadwal", headers=h_budi)).json()
    assert [k["pengguna_nama"] for k in sendiri] == ["Budi Kasir"]
    assert (await client.put(f"/jadwal/{budi.id}", headers=h_budi, json=_minggu())).status_code == 403


async def test_validasi_jadwal_dan_karyawan_toko_lain(client: AsyncClient, db_session: AsyncSession) -> None:
    a = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    b = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    url = f"/jadwal/{a.pengguna.id}"
    salah = [
        {"hari": [{"hari": 1, "shift": "pagi"}, {"hari": 1, "shift": "siang"}]},  # hari dobel
        {"hari": [{"hari": 8, "shift": "pagi"}]},
        {"hari": [{"hari": 1, "shift": "malam"}]},
        {"hari": [{"hari": 1, "shift": "pagi", "jam_mulai": "25:00"}]},
        {"hari": [{"hari": 1, "shift": "pagi", "jam_mulai": "15:00", "jam_selesai": "07:00"}]},
        {"hari": []},
    ]
    for badan in salah:
        assert (await client.put(url, headers=a.headers, json=badan)).status_code == 422, badan
    # Karyawan milik toko lain tidak bisa diatur
    assert (await client.put(f"/jadwal/{b.pengguna.id}", headers=a.headers, json=_minggu())).status_code == 404


async def test_jadwal_saya_hari_ini_dan_cuti_disetujui(client: AsyncClient, db_session: AsyncSession) -> None:
    owner = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    budi, h_budi = await _kasir(db_session, owner)
    await client.put(f"/jadwal/{budi.id}", headers=owner.headers, json=_minggu("pagi"))

    saya = (await client.get("/jadwal/saya", headers=h_budi, params={"tz_menit": 420})).json()
    assert len(saya["hari"]) == 7
    assert saya["hari_ini"]["shift"] == "pagi" and saya["hari_ini"]["cuti"] is None
    assert saya["hari_ini"]["jam_mulai"] == "07:00"

    sekarang = datetime.now(UTC) + timedelta(minutes=420)
    pengajuan = await client.post(
        "/cuti", headers=h_budi,
        json={"jenis": "sakit", "tanggal_mulai": sekarang.date().isoformat(), "tanggal_selesai": sekarang.date().isoformat()},
    )
    assert pengajuan.status_code == 201
    # Belum disetujui: belum tampil sebagai cuti
    assert (await client.get("/jadwal/saya", headers=h_budi, params={"tz_menit": 420})).json()["hari_ini"]["cuti"] is None
    await client.post(f"/cuti/{pengajuan.json()['id']}/putuskan", headers=owner.headers, json={"setuju": True})
    assert (await client.get("/jadwal/saya", headers=h_budi, params={"tz_menit": 420})).json()["hari_ini"]["cuti"] == "sakit"


async def test_alur_pengajuan_cuti(client: AsyncClient, db_session: AsyncSession) -> None:
    owner = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    budi, h_budi = await _kasir(db_session, owner)
    badan = {"jenis": "cuti", "tanggal_mulai": _tgl(5), "tanggal_selesai": _tgl(7), "alasan": "Acara keluarga"}

    ajukan = await client.post("/cuti", headers=h_budi, json=badan)
    assert ajukan.status_code == 201, ajukan.text
    cid = ajukan.json()["id"]
    assert ajukan.json()["status"] == "menunggu" and ajukan.json()["pengguna_nama"] == "Budi Kasir"

    # Tumpang tindih dengan pengajuan aktif ditolak
    assert (await client.post("/cuti", headers=h_budi, json={**badan, "tanggal_mulai": _tgl(7), "tanggal_selesai": _tgl(9)})).status_code == 409
    # Tanggal terbalik dan terlalu panjang
    assert (await client.post("/cuti", headers=h_budi, json={**badan, "tanggal_mulai": _tgl(9), "tanggal_selesai": _tgl(8)})).status_code == 422
    assert (await client.post("/cuti", headers=h_budi, json={**badan, "tanggal_mulai": _tgl(100), "tanggal_selesai": _tgl(170)})).status_code == 422

    # Pengelola melihat semua; kasir hanya miliknya; filter status
    assert len((await client.get("/cuti", headers=owner.headers)).json()) == 1
    assert len((await client.get("/cuti", headers=h_budi)).json()) == 1
    assert (await client.get("/cuti", headers=owner.headers, params={"status": "disetujui"})).json() == []

    # Kasir tidak boleh memutuskan; pengelola tidak boleh memutuskan miliknya sendiri
    assert (await client.post(f"/cuti/{cid}/putuskan", headers=h_budi, json={"setuju": True})).status_code == 403
    milik_owner = await client.post("/cuti", headers=owner.headers, json={**badan, "tanggal_mulai": _tgl(20), "tanggal_selesai": _tgl(21)})
    assert (await client.post(f"/cuti/{milik_owner.json()['id']}/putuskan", headers=owner.headers, json={"setuju": True})).status_code == 403

    putus = await client.post(f"/cuti/{cid}/putuskan", headers=owner.headers, json={"setuju": True, "catatan": "Oke"})
    assert putus.status_code == 200 and putus.json()["status"] == "disetujui"
    assert putus.json()["catatan_keputusan"] == "Oke" and putus.json()["diputuskan_oleh"] == str(owner.pengguna.id)
    # Tidak bisa diputuskan dua kali dan tidak bisa dibatalkan setelah diputuskan
    assert (await client.post(f"/cuti/{cid}/putuskan", headers=owner.headers, json={"setuju": False})).status_code == 409
    assert (await client.post(f"/cuti/{cid}/batalkan", headers=h_budi)).status_code == 409


async def test_batalkan_pengajuan_dan_ditolak_membebaskan_tanggal(client: AsyncClient, db_session: AsyncSession) -> None:
    owner = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    budi, h_budi = await _kasir(db_session, owner)
    _, h_ani = await _kasir(db_session, owner, "Ani Kasir")
    badan = {"jenis": "izin", "tanggal_mulai": _tgl(3), "tanggal_selesai": _tgl(3)}
    cid = (await client.post("/cuti", headers=h_budi, json=badan)).json()["id"]

    assert (await client.post(f"/cuti/{cid}/batalkan", headers=h_ani)).status_code == 403, "bukan pemiliknya"
    batal = await client.post(f"/cuti/{cid}/batalkan", headers=h_budi)
    assert batal.status_code == 200 and batal.json()["status"] == "dibatalkan"
    # Yang dibatalkan tidak lagi menghalangi pengajuan baru di tanggal yang sama
    kedua = await client.post("/cuti", headers=h_budi, json=badan)
    assert kedua.status_code == 201
    tolak = await client.post(f"/cuti/{kedua.json()['id']}/putuskan", headers=owner.headers, json={"setuju": False, "catatan": "Tim penuh"})
    assert tolak.json()["status"] == "ditolak"
    assert (await client.post("/cuti", headers=h_budi, json=badan)).status_code == 201, "yang ditolak membebaskan tanggal"


async def test_absen_masuk_terlambat_mengikuti_jadwal(client: AsyncClient, db_session: AsyncSession) -> None:
    owner = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    budi, h_budi = await _kasir(db_session, owner)

    # Atur jam setempat perangkat menjadi 12:00 apa pun jam server saat tes berjalan.
    sekarang = datetime.now(UTC)
    tz = 12 * 60 - (sekarang.hour * 60 + sekarang.minute)
    hari_ini = (sekarang + timedelta(minutes=tz)).isoweekday()

    async def coba(shift: str, mulai: str | None = None) -> str:
        badan = {"hari": [{"hari": hari_ini, "shift": shift, **({"jam_mulai": mulai, "jam_selesai": "23:00"} if mulai else {})}]}
        assert (await client.put(f"/jadwal/{budi.id}", headers=owner.headers, json=badan)).status_code == 200
        masuk = await client.post("/absensi/masuk", headers=h_budi, json={"tz_menit": tz})
        assert masuk.status_code == 201, masuk.text
        await client.post("/absensi/keluar", headers=h_budi, json={})
        return masuk.json()["status"]

    assert await coba("pagi", "07:00") == "terlambat", "12:00 lewat 07:10"
    assert await coba("pagi", "11:55") == "hadir", "12:00 masih dalam toleransi 10 menit"
    assert await coba("siang", "12:00") == "hadir"
    assert await coba("libur") == "hadir", "hari libur tidak dianggap terlambat"


async def test_absen_tanpa_jadwal_tetap_hadir(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    masuk = await client.post("/absensi/masuk", headers=toko.headers, json={"tz_menit": 420})
    assert masuk.status_code == 201 and masuk.json()["status"] == "hadir"
