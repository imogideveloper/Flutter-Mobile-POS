from datetime import UTC, datetime

from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import create_access_token
from app.models.akun import Pengguna, Role
from tests.conftest import buat_metode_bayar, buat_produk


async def _checkout_dan_void(client: AsyncClient, toko_a, produk, metode) -> None:
    resp = await client.post(
        "/transaksi",
        headers=toko_a.headers,
        json={
            "outlet_id": str(toko_a.outlet.id),
            "nomor_struk": "OUT1-AUD001",
            "tanggal": datetime.now(UTC).isoformat(),
            "items": [
                {"produk_id": str(produk.id), "nama_produk": produk.nama, "qty": "1", "harga_satuan": "15000"}
            ],
            "metode_bayar_id": str(metode.id),
            "total_bayar": "15000",
        },
    )
    transaksi_id = resp.json()["id"]
    await client.post(f"/transaksi/{transaksi_id}/void", headers=toko_a.headers, json={"alasan": "Uji audit log"})


async def test_owner_bisa_lihat_audit_log(client: AsyncClient, db_session: AsyncSession, toko_a) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id)
    metode = await buat_metode_bayar(db_session, toko_a.toko.id)
    await _checkout_dan_void(client, toko_a, produk, metode)

    resp = await client.get("/audit-log", headers=toko_a.headers)
    assert resp.status_code == 200
    aksi = {row["aksi"] for row in resp.json()}
    assert "void" in aksi


async def test_filter_audit_log_by_tabel(client: AsyncClient, db_session: AsyncSession, toko_a) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id)
    metode = await buat_metode_bayar(db_session, toko_a.toko.id)
    await _checkout_dan_void(client, toko_a, produk, metode)

    resp = await client.get("/audit-log", headers=toko_a.headers, params={"tabel": "transaksi"})
    assert resp.status_code == 200
    assert len(resp.json()) >= 1
    assert all(row["tabel"] == "transaksi" for row in resp.json())


async def test_kasir_tanpa_izin_lihat_audit_log_ditolak(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    kasir_role = (
        await db_session.execute(select(Role).where(Role.nama == "Kasir", Role.is_system.is_(True)))
    ).scalar_one()
    kasir = Pengguna(toko_id=toko_a.toko.id, role_id=kasir_role.id, nama="Kasir Biasa")
    db_session.add(kasir)
    await db_session.commit()
    token_kasir = create_access_token(pengguna_id=kasir.id, toko_id=toko_a.toko.id, role_id=kasir_role.id)

    resp = await client.get("/audit-log", headers={"Authorization": f"Bearer {token_kasir}"})
    assert resp.status_code == 403


async def test_audit_log_toko_lain_tidak_terlihat(
    client: AsyncClient, db_session: AsyncSession, toko_a, toko_b
) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id)
    metode = await buat_metode_bayar(db_session, toko_a.toko.id)
    await _checkout_dan_void(client, toko_a, produk, metode)

    resp = await client.get("/audit-log", headers=toko_b.headers)
    assert resp.status_code == 200
    assert resp.json() == []
