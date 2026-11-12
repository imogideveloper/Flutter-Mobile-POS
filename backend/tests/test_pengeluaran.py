import uuid

from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from tests.conftest import buat_toko_siap_pakai


def _badan(**ganti):
    data = {"tanggal": "2026-11-12", "kategori": "belanja_bahan", "jumlah": 150000, "catatan": "Biji kopi 5 kg"}
    data.update(ganti)
    return data


async def test_pengeluaran_digate_paket_gratis(client: AsyncClient, db_session: AsyncSession) -> None:
    gratis = await buat_toko_siap_pakai(db_session, nama_paket="Gratis")
    resp = await client.post("/pengeluaran", headers=gratis.headers, json=_badan())
    assert resp.status_code == 403
    assert resp.json()["detail"]["fitur"] == "expenses"


async def test_catat_daftar_ringkasan_dan_hapus(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Pro")
    h = toko.headers
    r1 = await client.post("/pengeluaran", headers=h, json=_badan(jumlah=150000))
    r2 = await client.post("/pengeluaran", headers=h, json=_badan(kategori="gas_lpg", jumlah=25000, catatan=None))
    r3 = await client.post("/pengeluaran", headers=h, json=_badan(jumlah=50000, tanggal="2026-11-13"))
    assert r1.status_code == r2.status_code == r3.status_code == 201

    daftar = (await client.get("/pengeluaran", headers=h, params={"dari": "2026-11-12", "sampai": "2026-11-12"})).json()
    assert daftar["total"] == 175000
    assert {k["kategori"]: k["total"] for k in daftar["per_kategori"]} == {"belanja_bahan": 150000, "gas_lpg": 25000}
    assert len(daftar["item"]) == 2

    semua = (await client.get("/pengeluaran", headers=h, params={"dari": "2026-11-01", "sampai": "2026-11-30"})).json()
    assert semua["total"] == 225000
    assert semua["per_kategori"][0]["kategori"] == "belanja_bahan"  # terbesar dulu

    hapus = await client.delete(f"/pengeluaran/{r2.json()['id']}", headers=h)
    assert hapus.status_code == 204
    setelah = (await client.get("/pengeluaran", headers=h, params={"dari": "2026-11-12", "sampai": "2026-11-12"})).json()
    assert setelah["total"] == 150000
    assert (await client.delete(f"/pengeluaran/{r2.json()['id']}", headers=h)).status_code == 404


async def test_catat_dengan_id_klien_idempoten(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Pro")
    id_klien = str(uuid.uuid4())
    a = await client.post("/pengeluaran", headers=toko.headers, json=_badan(id=id_klien))
    b = await client.post("/pengeluaran", headers=toko.headers, json=_badan(id=id_klien))
    assert a.status_code == 201 and b.status_code == 201
    assert a.json()["id"] == b.json()["id"] == id_klien
    daftar = (
        await client.get("/pengeluaran", headers=toko.headers, params={"dari": "2026-11-12", "sampai": "2026-11-12"})
    ).json()
    assert len(daftar["item"]) == 1


async def test_validasi_input(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Pro")
    h = toko.headers
    assert (await client.post("/pengeluaran", headers=h, json=_badan(jumlah=0))).status_code == 422
    assert (await client.post("/pengeluaran", headers=h, json=_badan(jumlah=-5))).status_code == 422
    assert (await client.post("/pengeluaran", headers=h, json=_badan(kategori="ngawur"))).status_code == 422
    assert (await client.post("/pengeluaran", headers=h, json=_badan(catatan="x" * 301))).status_code == 422
    assert (await client.post("/pengeluaran", headers=h, json=_badan(outlet_id=str(uuid.uuid4())))).status_code == 404
    salah = await client.get("/pengeluaran", headers=h, params={"dari": "2026-11-13", "sampai": "2026-11-12"})
    assert salah.status_code == 400


async def test_kasir_tidak_boleh_mengelola_pengeluaran(client: AsyncClient, db_session: AsyncSession) -> None:
    kasir = await buat_toko_siap_pakai(db_session, nama_role="Kasir", nama_paket="Pro")
    assert (await client.post("/pengeluaran", headers=kasir.headers, json=_badan())).status_code == 403
    r = await client.get("/pengeluaran", headers=kasir.headers, params={"dari": "2026-11-12", "sampai": "2026-11-12"})
    assert r.status_code == 403


async def test_pengeluaran_terisolasi_antar_toko(client: AsyncClient, db_session: AsyncSession) -> None:
    a = await buat_toko_siap_pakai(db_session, nama_paket="Pro")
    b = await buat_toko_siap_pakai(db_session, nama_paket="Pro")
    dibuat = await client.post("/pengeluaran", headers=a.headers, json=_badan())
    rentang = {"dari": "2026-11-01", "sampai": "2026-11-30"}
    assert (await client.get("/pengeluaran", headers=b.headers, params=rentang)).json()["total"] == 0
    assert (await client.delete(f"/pengeluaran/{dibuat.json()['id']}", headers=b.headers)).status_code == 404
    # id klien milik toko lain tidak boleh dipakai ulang
    bentrok = await client.post("/pengeluaran", headers=b.headers, json=_badan(id=dibuat.json()["id"]))
    assert bentrok.status_code == 409
