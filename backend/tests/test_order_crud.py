"""Tahap 5 B.5 - PATCH/DELETE tipe_order & meja, CRUD tipe_order_pajak
(gate service_per_tipe_order)."""

from decimal import Decimal

from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.audit import AuditLog
from app.models.order import Meja, TipeOrder
from app.models.promo import Pajak
from tests.conftest import buat_toko_siap_pakai


async def test_tipe_order_patch_delete_digate_fitur(client: AsyncClient, db_session: AsyncSession) -> None:
    toko_gratis = await buat_toko_siap_pakai(db_session, nama_paket="Gratis")
    tipe = TipeOrder(toko_id=toko_gratis.toko.id, nama="Dine In")
    db_session.add(tipe)
    await db_session.commit()

    resp = await client.patch(
        f"/tipe-order/{tipe.id}", headers=toko_gratis.headers, json={"nama": "Makan di tempat"}
    )
    assert resp.status_code == 403
    assert resp.json()["detail"]["kode"] == "fitur_terkunci"


async def test_tipe_order_patch_delete(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    tipe = TipeOrder(toko_id=toko.toko.id, nama="Dine In")
    db_session.add(tipe)
    await db_session.commit()

    resp = await client.patch(
        f"/tipe-order/{tipe.id}", headers=toko.headers, json={"nama": "Makan di tempat", "markup_persen": "5"}
    )
    assert resp.status_code == 200
    assert resp.json()["nama"] == "Makan di tempat"
    assert Decimal(resp.json()["markup_persen"]) == Decimal("5")

    resp2 = await client.delete(f"/tipe-order/{tipe.id}", headers=toko.headers)
    assert resp2.status_code == 204
    await db_session.refresh(tipe)
    assert tipe.deleted_at is not None

    audit_rows = (
        await db_session.execute(select(AuditLog).where(AuditLog.aksi.in_(["ubah_tipe_order", "hapus_tipe_order"])))
    ).scalars().all()
    assert len(audit_rows) == 2


async def test_meja_patch_delete(client: AsyncClient, db_session: AsyncSession, toko_a) -> None:
    meja = Meja(outlet_id=toko_a.outlet.id, nama="Meja 1")
    db_session.add(meja)
    await db_session.commit()

    resp = await client.patch(
        f"/outlets/{toko_a.outlet.id}/meja/{meja.id}", headers=toko_a.headers,
        json={"nama": "Meja VIP 1", "kapasitas": 6},
    )
    assert resp.status_code == 200
    assert resp.json()["nama"] == "Meja VIP 1"
    assert resp.json()["kapasitas"] == 6

    resp2 = await client.delete(f"/outlets/{toko_a.outlet.id}/meja/{meja.id}", headers=toko_a.headers)
    assert resp2.status_code == 204
    await db_session.refresh(meja)
    assert meja.deleted_at is not None


async def test_tipe_order_pajak_link_unlink_digate_fitur(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    tipe = TipeOrder(toko_id=toko.toko.id, nama="Dine In")
    db_session.add(tipe)
    await db_session.flush()
    pajak = Pajak(toko_id=toko.toko.id, nama="Service", tipe="service", persen=Decimal("5"))
    db_session.add(pajak)
    await db_session.commit()

    resp = await client.post(f"/tipe-order/{tipe.id}/pajak/{pajak.id}", headers=toko.headers)
    assert resp.status_code == 204

    resp_dobel = await client.post(f"/tipe-order/{tipe.id}/pajak/{pajak.id}", headers=toko.headers)
    assert resp_dobel.status_code == 204

    resp2 = await client.get(f"/tipe-order/{tipe.id}/pajak", headers=toko.headers)
    assert len(resp2.json()) == 1
    assert resp2.json()[0]["nama_pajak"] == "Service"

    resp3 = await client.delete(f"/tipe-order/{tipe.id}/pajak/{pajak.id}", headers=toko.headers)
    assert resp3.status_code == 204
    resp4 = await client.get(f"/tipe-order/{tipe.id}/pajak", headers=toko.headers)
    assert resp4.json() == []
