from decimal import Decimal

from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.outlet import Paket
from app.models.produk import Kategori, Produk
from tests.conftest import buat_produk, buat_toko_siap_pakai


def _baris(nama: str, **lain) -> dict:
    return {"nama": nama, "harga_jual": 15000, "hpp": 6000, **lain}


async def _produk_toko(db: AsyncSession, toko_id) -> list[Produk]:
    return list((await db.execute(select(Produk).where(Produk.toko_id == toko_id))).scalars())


async def test_impor_menyimpan_produk_dan_membuat_kategori_baru(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Pro")
    db_session.add(Kategori(toko_id=toko.toko.id, nama="Kopi"))
    await db_session.commit()

    r = await client.post(
        "/produk/impor",
        headers=toko.headers,
        json={
            "baris": [
                _baris("Kopi Susu", kategori="kopi", sku="KS-1"),  # kategori sudah ada (tak peka huruf)
                _baris("Roti Bakar", kategori="Makanan", barcode="899001"),
                _baris("Teh Tawar", kategori=" makanan "),  # kategori baru yang sama, dipakai ulang
                _baris("Air Mineral"),
            ]
        },
    )
    assert r.status_code == 200, r.text
    b = r.json()
    assert b["diterima"] == 4 and b["ditolak"] == 0 and b["simulasi"] is False
    assert b["kategori_baru"] == ["Makanan"]

    produk = {p.nama: p for p in await _produk_toko(db_session, toko.toko.id)}
    assert set(produk) == {"Kopi Susu", "Roti Bakar", "Teh Tawar", "Air Mineral"}
    assert produk["Kopi Susu"].harga_jual == Decimal("15000") and produk["Kopi Susu"].hpp == Decimal("6000")
    assert produk["Air Mineral"].kategori_id is None
    assert produk["Roti Bakar"].kategori_id == produk["Teh Tawar"].kategori_id
    kategori = (await db_session.execute(select(Kategori).where(Kategori.toko_id == toko.toko.id))).scalars().all()
    assert sorted(k.nama for k in kategori) == ["Kopi", "Makanan"]


async def test_impor_simulasi_tidak_menyimpan_apa_pun(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Pro")
    r = await client.post(
        "/produk/impor",
        headers=toko.headers,
        json={"simulasi": True, "baris": [_baris("Kopi", kategori="Baru"), _baris("")]},
    )
    assert r.status_code == 200
    b = r.json()
    assert b["simulasi"] is True and b["diterima"] == 1 and b["ditolak"] == 1
    assert b["kategori_baru"] == ["Baru"]
    assert await _produk_toko(db_session, toko.toko.id) == []
    assert (await db_session.execute(select(Kategori).where(Kategori.toko_id == toko.toko.id))).scalars().all() == []


async def test_impor_menolak_baris_salah_tapi_menerima_yang_valid(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Pro")
    existing = await buat_produk(db_session, toko.toko.id, nama="Lama")
    existing.sku = "DUP-1"
    existing.barcode = "111"
    await db_session.commit()

    r = await client.post(
        "/produk/impor",
        headers=toko.headers,
        json={
            "baris": [
                _baris("A", sku="DUP-1"),  # SKU sudah dipakai produk lama
                _baris("B", barcode="111"),  # barcode sudah dipakai
                _baris("C", sku="BARU-1"),
                _baris("D", sku="baru-1"),  # SKU sama dengan baris C (tak peka huruf)
                _baris("", sku="X"),  # nama kosong
                {"nama": "E", "harga_jual": -1},  # harga negatif
                _baris("F"),
            ]
        },
    )
    assert r.status_code == 200, r.text
    b = r.json()
    status_per_nomor = {h["nomor"]: h["status"] for h in b["hasil"]}
    assert status_per_nomor == {1: "ditolak", 2: "ditolak", 3: "diterima", 4: "ditolak", 5: "ditolak", 6: "ditolak", 7: "diterima"}
    assert b["diterima"] == 2 and b["ditolak"] == 5
    assert "SKU" in b["hasil"][0]["pesan"] and "Barcode" in b["hasil"][1]["pesan"]
    nama = {p.nama for p in await _produk_toko(db_session, toko.toko.id)}
    assert nama == {"Lama", "C", "F"}


async def test_impor_mengikuti_kuota_produk_paket(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Pro")
    paket = (await db_session.execute(select(Paket).where(Paket.nama == "Pro"))).scalar_one()
    paket.maks_produk = 2
    await db_session.commit()
    await buat_produk(db_session, toko.toko.id, nama="Sudah Ada")

    r = await client.post("/produk/impor", headers=toko.headers, json={"baris": [_baris("A"), _baris("B"), _baris("C")]})
    b = r.json()
    assert b["diterima"] == 1 and b["ditolak"] == 2
    assert "Kuota" in b["hasil"][1]["pesan"]
    assert len(await _produk_toko(db_session, toko.toko.id)) == 2


async def test_impor_digate_paket_izin_dan_batas_baris(client: AsyncClient, db_session: AsyncSession) -> None:
    gratis = await buat_toko_siap_pakai(db_session, nama_paket="Gratis")
    r = await client.post("/produk/impor", headers=gratis.headers, json={"baris": [_baris("A")]})
    assert r.status_code == 403 and r.json()["detail"]["fitur"] == "ekspor_impor"

    kasir = await buat_toko_siap_pakai(db_session, nama_role="Kasir", nama_paket="Pro")
    assert (await client.post("/produk/impor", headers=kasir.headers, json={"baris": [_baris("A")]})).status_code == 403

    pro = await buat_toko_siap_pakai(db_session, nama_paket="Pro")
    assert (await client.post("/produk/impor", headers=pro.headers, json={"baris": []})).status_code == 422
    banyak = [_baris(f"P{i}") for i in range(501)]
    assert (await client.post("/produk/impor", headers=pro.headers, json={"baris": banyak})).status_code == 422


async def test_impor_mode_perbarui_mengubah_produk_lama_lewat_sku(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Pro")
    tid = toko.toko.id
    h = toko.headers
    await client.post("/produk/impor", headers=h, json={"baris": [_baris("Kopi Susu", sku="KS-1", kategori="Kopi")]})

    # Tanpa mode perbarui: SKU yang sama ditolak (perilaku lama).
    ditolak = await client.post("/produk/impor", headers=h, json={"baris": [_baris("Kopi Susu v2", sku="KS-1")]})
    assert ditolak.json()["ditolak"] == 1

    # Mode perbarui: harga berubah, kolom kosong (hpp) tidak mengubah nilai lama.
    r = await client.post(
        "/produk/impor",
        headers=h,
        json={
            "perbarui_yang_ada": True,
            "baris": [
                {"nama": "Kopi Susu Gula Aren", "sku": "ks-1", "harga_jual": 20000, "kategori": "Minuman"},
                _baris("Produk Baru", sku="PB-1"),
            ],
        },
    )
    assert r.status_code == 200, r.text
    b = r.json()
    assert b["diterima"] == 2 and b["diperbarui"] == 1 and b["ditolak"] == 0
    assert [x["status"] for x in b["hasil"]] == ["diperbarui", "diterima"]

    db_session.expire_all()
    produk = {p.sku: p for p in await _produk_toko(db_session, tid)}
    assert len(produk) == 2
    assert produk["KS-1"].nama == "Kopi Susu Gula Aren"
    assert produk["KS-1"].harga_jual == Decimal("20000")
    assert produk["KS-1"].hpp == Decimal("6000")  # tidak berubah
    assert b["kategori_baru"] == ["Minuman"]


async def test_impor_perbarui_simulasi_tidak_menyimpan_dan_sku_barcode_bentrok_ditolak(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Pro")
    tid = toko.toko.id
    h = toko.headers
    await client.post(
        "/produk/impor", headers=h, json={"baris": [_baris("A", sku="A-1", barcode="111"), _baris("B", sku="B-1", barcode="222")]}
    )

    r = await client.post(
        "/produk/impor",
        headers=h,
        json={
            "perbarui_yang_ada": True,
            "simulasi": True,
            "baris": [{"nama": "A baru", "sku": "A-1", "harga_jual": 1}, {"nama": "X", "sku": "A-1", "barcode": "222"}],
        },
    )
    b = r.json()
    assert [x["status"] for x in b["hasil"]] == ["diperbarui", "ditolak"]
    db_session.expire_all()
    assert {p.nama for p in await _produk_toko(db_session, tid)} == {"A", "B"}


async def test_impor_stok_awal_mengisi_stok_produk_baru(client: AsyncClient, db_session: AsyncSession) -> None:
    from app.models.stok import MutasiStok, Stok

    toko = await buat_toko_siap_pakai(db_session, nama_paket="Pro")
    h = toko.headers
    r = await client.post(
        "/produk/impor",
        headers=h,
        json={
            "outlet_id": str(toko.outlet.id),
            "baris": [_baris("Kopi", sku="K-1", stok_awal=12), _baris("Teh", sku="T-1")],
        },
    )
    assert r.json()["diterima"] == 2

    stok = (await db_session.execute(select(Stok))).scalars().all()
    assert len(stok) == 1 and stok[0].jumlah == Decimal("12") and stok[0].outlet_id == toko.outlet.id
    mutasi = (await db_session.execute(select(MutasiStok))).scalars().all()
    assert [m.jenis for m in mutasi] == ["stok_awal"]

    tanpa_outlet = await client.post("/produk/impor", headers=h, json={"baris": [_baris("Gula", stok_awal=5)]})
    assert tanpa_outlet.json()["ditolak"] == 1
    salah_outlet = await client.post(
        "/produk/impor", headers=h, json={"outlet_id": "00000000-0000-0000-0000-000000000001", "baris": [_baris("Z")]}
    )
    assert salah_outlet.status_code == 404


async def test_impor_stok_awal_butuh_izin_stok_kelola(client: AsyncClient, db_session: AsyncSession) -> None:
    from sqlalchemy import delete

    from app.models.akun import Izin, Role, RoleIzin

    toko = await buat_toko_siap_pakai(db_session, nama_role="Manajer", nama_paket="Pro")
    manajer = (await db_session.execute(select(Role).where(Role.nama == "Manajer", Role.is_system.is_(True)))).scalar_one()
    izin_stok = (await db_session.execute(select(Izin.id).where(Izin.kode == "stok.kelola"))).scalar_one()
    await db_session.execute(delete(RoleIzin).where(RoleIzin.role_id == manajer.id, RoleIzin.izin_id == izin_stok))
    await db_session.commit()

    r = await client.post(
        "/produk/impor",
        headers=toko.headers,
        json={"outlet_id": str(toko.outlet.id), "baris": [_baris("Kopi", stok_awal=3), _baris("Teh")]},
    )
    b = r.json()
    assert b["diterima"] == 1 and b["ditolak"] == 1
    assert "stok.kelola" in b["hasil"][0]["pesan"]
