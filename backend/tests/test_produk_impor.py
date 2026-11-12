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
