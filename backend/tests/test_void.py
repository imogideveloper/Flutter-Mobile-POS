import uuid
from datetime import UTC, datetime
from decimal import Decimal

from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.akun import Pengguna, Role
from app.models.audit import AuditLog
from app.models.stok import Stok
from app.core.security import create_access_token
from tests.conftest import buat_metode_bayar, buat_produk


async def _checkout(client: AsyncClient, toko_a, produk, metode, nomor_struk: str) -> str:
    resp = await client.post(
        "/transaksi",
        headers=toko_a.headers,
        json={
            "outlet_id": str(toko_a.outlet.id),
            "nomor_struk": nomor_struk,
            "tanggal": datetime.now(UTC).isoformat(),
            "items": [
                {"produk_id": str(produk.id), "nama_produk": produk.nama, "qty": "2", "harga_satuan": "15000"}
            ],
            "metode_bayar_id": str(metode.id),
            "total_bayar": "30000",
        },
    )
    assert resp.status_code == 201
    return resp.json()["id"]


async def test_owner_bisa_void_dan_stok_dikembalikan(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id)
    metode = await buat_metode_bayar(db_session, toko_a.toko.id)
    transaksi_id = await _checkout(client, toko_a, produk, metode, "OUT1-0010")

    stok_setelah_jual = (
        await db_session.execute(select(Stok).where(Stok.produk_id == produk.id))
    ).scalar_one()
    assert stok_setelah_jual.jumlah == Decimal("-2")

    resp = await client.post(
        f"/transaksi/{transaksi_id}/void", headers=toko_a.headers, json={"alasan": "Salah input"}
    )
    assert resp.status_code == 200
    assert resp.json()["status"] == "void"
    assert resp.json()["alasan_void"] == "Salah input"

    stok_setelah_void = (
        await db_session.execute(select(Stok).where(Stok.produk_id == produk.id))
    ).scalar_one()
    assert stok_setelah_void.jumlah == Decimal("0")

    audit_rows = (await db_session.execute(select(AuditLog).where(AuditLog.aksi == "void"))).scalars().all()
    assert len(audit_rows) == 1
    assert audit_rows[0].record_id == uuid.UUID(transaksi_id)


async def test_kasir_tanpa_izin_void_ditolak(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id)
    metode = await buat_metode_bayar(db_session, toko_a.toko.id)
    transaksi_id = await _checkout(client, toko_a, produk, metode, "OUT1-0011")

    kasir_role = (
        await db_session.execute(select(Role).where(Role.nama == "Kasir", Role.is_system.is_(True)))
    ).scalar_one()
    kasir = Pengguna(toko_id=toko_a.toko.id, role_id=kasir_role.id, nama="Kasir Biasa")
    db_session.add(kasir)
    await db_session.commit()
    token_kasir = create_access_token(pengguna_id=kasir.id, toko_id=toko_a.toko.id, role_id=kasir_role.id)

    resp = await client.post(
        f"/transaksi/{transaksi_id}/void",
        headers={"Authorization": f"Bearer {token_kasir}"},
        json={"alasan": "Coba-coba"},
    )
    assert resp.status_code == 403


async def test_void_dua_kali_ditolak(client: AsyncClient, db_session: AsyncSession, toko_a) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id)
    metode = await buat_metode_bayar(db_session, toko_a.toko.id)
    transaksi_id = await _checkout(client, toko_a, produk, metode, "OUT1-0012")

    resp1 = await client.post(
        f"/transaksi/{transaksi_id}/void", headers=toko_a.headers, json={"alasan": "Salah input"}
    )
    assert resp1.status_code == 200

    resp2 = await client.post(
        f"/transaksi/{transaksi_id}/void", headers=toko_a.headers, json={"alasan": "Coba lagi"}
    )
    assert resp2.status_code == 409
