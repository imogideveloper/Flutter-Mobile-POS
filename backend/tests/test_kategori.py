"""CRUD kategori produk (GET/POST sudah lama ada, PATCH/DELETE BARU -
dulu kategori cuma bisa dibuat lewat API, tidak pernah bisa diubah nama/
urutan atau dihapus, jadi app Flutter tidak punya jalan utk mengelolanya
sama sekali meski tabelnya sudah ada)."""

import uuid

from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.produk import Kategori


async def test_tambah_dan_daftar_kategori(client: AsyncClient, toko_a) -> None:
    resp = await client.post(
        "/kategori", headers=toko_a.headers, json={"nama": "Minuman", "warna": "#0F6E58", "urutan": 0}
    )
    assert resp.status_code == 201
    body = resp.json()
    assert body["nama"] == "Minuman"
    assert body["warna"] == "#0F6E58"

    resp_list = await client.get("/kategori", headers=toko_a.headers)
    assert resp_list.status_code == 200
    assert any(k["nama"] == "Minuman" for k in resp_list.json())


async def test_ubah_kategori(client: AsyncClient, db_session: AsyncSession, toko_a) -> None:
    resp = await client.post("/kategori", headers=toko_a.headers, json={"nama": "Makanan"})
    kategori_id = resp.json()["id"]

    resp_patch = await client.patch(
        f"/kategori/{kategori_id}", headers=toko_a.headers, json={"nama": "Makanan Berat", "urutan": 2}
    )
    assert resp_patch.status_code == 200
    assert resp_patch.json()["nama"] == "Makanan Berat"
    assert resp_patch.json()["urutan"] == 2


async def test_hapus_kategori_soft_delete(client: AsyncClient, db_session: AsyncSession, toko_a) -> None:
    resp = await client.post("/kategori", headers=toko_a.headers, json={"nama": "Snack"})
    kategori_id = resp.json()["id"]

    resp_del = await client.delete(f"/kategori/{kategori_id}", headers=toko_a.headers)
    assert resp_del.status_code == 204

    resp_list = await client.get("/kategori", headers=toko_a.headers)
    assert all(k["id"] != kategori_id for k in resp_list.json())

    kategori_row = await db_session.get(Kategori, uuid.UUID(kategori_id))
    assert kategori_row.deleted_at is not None


async def test_ubah_hapus_kategori_tidak_ditemukan(client: AsyncClient, toko_a) -> None:
    id_asal = "00000000-0000-0000-0000-000000000000"
    resp_patch = await client.patch(f"/kategori/{id_asal}", headers=toko_a.headers, json={"nama": "X"})
    assert resp_patch.status_code == 404

    resp_del = await client.delete(f"/kategori/{id_asal}", headers=toko_a.headers)
    assert resp_del.status_code == 404


async def test_kategori_toko_lain_tidak_bisa_diubah(
    client: AsyncClient, db_session: AsyncSession, toko_a, toko_b
) -> None:
    kategori_b = Kategori(toko_id=toko_b.toko.id, nama="Punya Toko B")
    db_session.add(kategori_b)
    await db_session.commit()
    await db_session.refresh(kategori_b)

    resp = await client.patch(
        f"/kategori/{kategori_b.id}", headers=toko_a.headers, json={"nama": "Dibajak"}
    )
    assert resp.status_code == 404
