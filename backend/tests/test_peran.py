"""Peran dan hak akses: buat/ubah/hapus peran buatan toko, peran bawaan terkunci, tidak boleh eskalasi hak."""

from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.akun import Izin, Pengguna, Role, RoleIzin
from tests.conftest import buat_toko_siap_pakai


async def test_daftar_izin_memuat_katalog_lengkap(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Pro")
    resp = await client.get("/izin", headers=toko.headers)
    assert resp.status_code == 200
    kode = {i["kode"] for i in resp.json()}
    assert {"transaksi.buat", "bon.jual", "laporan.keuangan", "produk.lihat_margin"} <= kode
    assert len(kode) == 23


async def test_buat_ubah_hapus_peran(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Pro")
    h = toko.headers

    dibuat = await client.post("/roles", headers=h, json={"nama": "Supervisor", "izin_kode": ["transaksi.buat", "bon.jual"]})
    assert dibuat.status_code == 201
    peran = dibuat.json()
    assert peran["is_system"] is False
    assert peran["izin_kode"] == ["bon.jual", "transaksi.buat"]

    assert any(r["id"] == peran["id"] for r in (await client.get("/roles", headers=h)).json())
    assert (await client.get(f"/roles/{peran['id']}", headers=h)).json()["nama"] == "Supervisor"

    diubah = await client.patch(
        f"/roles/{peran['id']}", headers=h, json={"nama": "Supervisor Shift", "izin_kode": ["transaksi.buat"]}
    )
    assert diubah.status_code == 200
    assert diubah.json()["nama"] == "Supervisor Shift"
    assert diubah.json()["izin_kode"] == ["transaksi.buat"]

    assert (await client.delete(f"/roles/{peran['id']}", headers=h)).status_code == 204
    assert all(r["id"] != peran["id"] for r in (await client.get("/roles", headers=h)).json())
    assert (await client.get(f"/roles/{peran['id']}", headers=h)).status_code == 404


async def test_peran_bawaan_tidak_bisa_diubah_atau_dihapus(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Pro")
    kasir = (await db_session.execute(select(Role).where(Role.nama == "Kasir", Role.is_system.is_(True)))).scalar_one()
    h = toko.headers
    assert (await client.patch(f"/roles/{kasir.id}", headers=h, json={"nama": "X"})).status_code == 400
    assert (await client.delete(f"/roles/{kasir.id}", headers=h)).status_code == 400


async def test_validasi_nama_dan_kode_izin(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Pro")
    h = toko.headers
    assert (await client.post("/roles", headers=h, json={"nama": "  ", "izin_kode": []})).status_code == 422
    assert (await client.post("/roles", headers=h, json={"nama": "Baru", "izin_kode": ["ngawur.izin"]})).status_code == 422
    assert (await client.post("/roles", headers=h, json={"nama": "kasir", "izin_kode": []})).status_code == 409
    assert (await client.post("/roles", headers=h, json={"nama": "Ganda", "izin_kode": []})).status_code == 201
    assert (await client.post("/roles", headers=h, json={"nama": "ganda", "izin_kode": []})).status_code == 409


async def test_peran_yang_dipakai_karyawan_tidak_bisa_dihapus(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Pro")
    h = toko.headers
    peran = (await client.post("/roles", headers=h, json={"nama": "Pelayan", "izin_kode": ["transaksi.buat"]})).json()
    karyawan = await client.post("/pengguna", headers=h, json={"role_id": peran["id"], "nama": "Budi"})
    assert karyawan.status_code == 201

    detail = (await client.get(f"/roles/{peran['id']}", headers=h)).json()
    assert detail["jumlah_pengguna"] == 1
    assert (await client.delete(f"/roles/{peran['id']}", headers=h)).status_code == 400


async def test_tidak_bisa_memberi_izin_yang_tidak_dimiliki(client: AsyncClient, db_session: AsyncSession) -> None:
    """Manajer yang diberi pengguna.kelola tetap tidak boleh membuat peran dengan pengaturan.kelola."""
    toko = await buat_toko_siap_pakai(db_session, nama_role="Manajer", nama_paket="Pro")
    manajer = (await db_session.execute(select(Role).where(Role.nama == "Manajer", Role.is_system.is_(True)))).scalar_one()
    izin = (await db_session.execute(select(Izin).where(Izin.kode == "pengguna.kelola"))).scalar_one()
    db_session.add(RoleIzin(role_id=manajer.id, izin_id=izin.id))
    await db_session.commit()

    h = toko.headers
    assert (await client.post("/roles", headers=h, json={"nama": "Naik", "izin_kode": ["pengaturan.kelola"]})).status_code == 403
    assert (await client.post("/roles", headers=h, json={"nama": "Aman", "izin_kode": ["transaksi.buat"]})).status_code == 201


async def test_kasir_tidak_boleh_mengelola_peran(client: AsyncClient, db_session: AsyncSession) -> None:
    kasir = await buat_toko_siap_pakai(db_session, nama_role="Kasir", nama_paket="Pro")
    assert (await client.post("/roles", headers=kasir.headers, json={"nama": "Z", "izin_kode": []})).status_code == 403


async def test_peran_toko_lain_tidak_terlihat(client: AsyncClient, db_session: AsyncSession) -> None:
    a = await buat_toko_siap_pakai(db_session, nama_paket="Pro")
    b = await buat_toko_siap_pakai(db_session, nama_paket="Pro")
    peran = (await client.post("/roles", headers=a.headers, json={"nama": "Rahasia A", "izin_kode": []})).json()
    assert (await client.get(f"/roles/{peran['id']}", headers=b.headers)).status_code == 404
    assert (await client.patch(f"/roles/{peran['id']}", headers=b.headers, json={"nama": "Curi"})).status_code == 404
    assert (await client.delete(f"/roles/{peran['id']}", headers=b.headers)).status_code == 404
    assert all(r["nama"] != "Rahasia A" for r in (await client.get("/roles", headers=b.headers)).json())
    assert Pengguna is not None
