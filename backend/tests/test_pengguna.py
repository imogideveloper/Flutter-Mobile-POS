from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.akun import Role
from tests.conftest import buat_toko_siap_pakai

# kelola_karyawan adalah fitur tingkat 1 (Pro) - toko_a/toko_b fixture
# default-nya paket Gratis, jadi tes CRUD/isolasi pengguna di file ini
# SENGAJA pakai toko Bisnis lokal (bukan toko_a/toko_b) supaya tidak
# tercampur dgn tes gating fitur itu sendiri (lihat tests/test_gating_fitur.py).


async def test_tambah_pengguna_dengan_role_kasir(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    kasir_role = (
        await db_session.execute(select(Role).where(Role.nama == "Kasir", Role.is_system.is_(True)))
    ).scalar_one()

    resp = await client.post(
        "/pengguna",
        headers=toko.headers,
        json={
            "role_id": str(kasir_role.id),
            "nama": "Budi Kasir",
            "pin": "4321",
            "outlet_ids": [str(toko.outlet.id)],
        },
    )
    assert resp.status_code == 201
    assert resp.json()["nama"] == "Budi Kasir"

    daftar = await client.get("/pengguna", headers=toko.headers)
    assert len(daftar.json()) == 2  # owner (toko fixture) + Budi


async def test_daftar_role_termasuk_bawaan_sistem(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    resp = await client.get("/roles", headers=toko.headers)
    assert resp.status_code == 200
    nama_role = {r["nama"] for r in resp.json()}
    assert {"Owner", "Manajer", "Kasir"}.issubset(nama_role)


async def test_pengguna_toko_b_tidak_terlihat_toko_a(client: AsyncClient, db_session: AsyncSession) -> None:
    toko_a = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    toko_b = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")

    resp = await client.get("/pengguna", headers=toko_a.headers)
    id_pengguna = {p["id"] for p in resp.json()}
    assert str(toko_b.pengguna.id) not in id_pengguna
    assert str(toko_a.pengguna.id) in id_pengguna
