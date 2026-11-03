"""Tahap 5 B.3/B.4 - PATCH/DELETE promo (+produk/outlet linking),
PATCH/DELETE pajak."""

import uuid
from decimal import Decimal

from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.audit import AuditLog
from app.models.promo import Pajak, Promo, PromoOutlet, PromoProduk
from tests.conftest import buat_produk, buat_toko_siap_pakai


async def test_ubah_pajak_tercatat_audit(client: AsyncClient, db_session: AsyncSession, toko_a) -> None:
    pajak = Pajak(toko_id=toko_a.toko.id, nama="PPN", persen=Decimal("10"))
    db_session.add(pajak)
    await db_session.commit()

    resp = await client.patch(f"/pajak/{pajak.id}", headers=toko_a.headers, json={"persen": "11"})
    assert resp.status_code == 200
    assert Decimal(resp.json()["persen"]) == Decimal("11")

    audit = (await db_session.execute(select(AuditLog).where(AuditLog.aksi == "ubah_pajak"))).scalar_one()
    assert audit.data_lama["persen"] == "10"
    assert audit.data_baru["persen"] == "11"


async def test_hapus_pajak_soft_delete(client: AsyncClient, db_session: AsyncSession, toko_a) -> None:
    pajak = Pajak(toko_id=toko_a.toko.id, nama="PPN", persen=Decimal("10"))
    db_session.add(pajak)
    await db_session.commit()

    resp = await client.delete(f"/pajak/{pajak.id}", headers=toko_a.headers)
    assert resp.status_code == 204
    await db_session.refresh(pajak)
    assert pajak.deleted_at is not None

    resp2 = await client.get("/pajak", headers=toko_a.headers)
    assert pajak.id not in {uuid.UUID(p["id"]) for p in resp2.json()}


async def test_promo_patch_delete_digate_fitur_diskon(client: AsyncClient, db_session: AsyncSession) -> None:
    toko_gratis = await buat_toko_siap_pakai(db_session, nama_paket="Gratis")
    promo = Promo(toko_id=toko_gratis.toko.id, nama="Promo", tipe="nominal", nilai=Decimal("1000"))
    db_session.add(promo)
    await db_session.commit()

    resp = await client.patch(f"/promo/{promo.id}", headers=toko_gratis.headers, json={"nama": "Coba"})
    assert resp.status_code == 403
    assert resp.json()["detail"]["kode"] == "fitur_terkunci"


async def test_ubah_dan_hapus_promo(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    promo = Promo(toko_id=toko.toko.id, nama="Promo Lama", tipe="nominal", nilai=Decimal("1000"))
    db_session.add(promo)
    await db_session.commit()

    resp = await client.patch(f"/promo/{promo.id}", headers=toko.headers, json={"nama": "Promo Baru"})
    assert resp.status_code == 200
    assert resp.json()["nama"] == "Promo Baru"

    resp2 = await client.delete(f"/promo/{promo.id}", headers=toko.headers)
    assert resp2.status_code == 204
    await db_session.refresh(promo)
    assert promo.deleted_at is not None

    audit_rows = (
        await db_session.execute(select(AuditLog).where(AuditLog.aksi.in_(["ubah_promo", "hapus_promo"])))
    ).scalars().all()
    assert len(audit_rows) == 2


async def test_atur_promo_produk_replace_all(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    promo = Promo(
        toko_id=toko.toko.id, nama="Promo Produk", tipe="nominal", nilai=Decimal("1000"), cakupan="produk",
    )
    db_session.add(promo)
    await db_session.commit()
    produk1 = await buat_produk(db_session, toko.toko.id, nama="Produk 1")
    produk2 = await buat_produk(db_session, toko.toko.id, nama="Produk 2")

    resp = await client.put(
        f"/promo/{promo.id}/produk", headers=toko.headers,
        json={"ids": [str(produk1.id), str(produk2.id)]},
    )
    assert resp.status_code == 204
    rows = (
        await db_session.execute(select(PromoProduk).where(PromoProduk.promo_id == promo.id))
    ).scalars().all()
    assert len(rows) == 2

    # Replace-all dgn hanya 1 id - harus TIMPA, bukan tambah.
    resp2 = await client.put(
        f"/promo/{promo.id}/produk", headers=toko.headers, json={"ids": [str(produk1.id)]}
    )
    assert resp2.status_code == 204
    rows2 = (
        await db_session.execute(select(PromoProduk).where(PromoProduk.promo_id == promo.id))
    ).scalars().all()
    assert len(rows2) == 1

    resp3 = await client.get(f"/promo/{promo.id}/produk", headers=toko.headers)
    assert resp3.json() == [str(produk1.id)]


async def test_atur_promo_produk_tolak_produk_toko_lain(client: AsyncClient, db_session: AsyncSession) -> None:
    toko_a = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    toko_b = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    promo = Promo(
        toko_id=toko_a.toko.id, nama="Promo Produk", tipe="nominal", nilai=Decimal("1000"), cakupan="produk",
    )
    db_session.add(promo)
    await db_session.commit()
    produk_b = await buat_produk(db_session, toko_b.toko.id, nama="Produk Toko B")

    resp = await client.put(
        f"/promo/{promo.id}/produk", headers=toko_a.headers, json={"ids": [str(produk_b.id)]}
    )
    assert resp.status_code == 404


async def test_atur_promo_outlet_replace_all(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    promo = Promo(toko_id=toko.toko.id, nama="Promo Outlet", tipe="nominal", nilai=Decimal("1000"))
    db_session.add(promo)
    await db_session.commit()

    resp = await client.put(
        f"/promo/{promo.id}/outlet", headers=toko.headers, json={"ids": [str(toko.outlet.id)]}
    )
    assert resp.status_code == 204
    rows = (
        await db_session.execute(select(PromoOutlet).where(PromoOutlet.promo_id == promo.id))
    ).scalars().all()
    assert len(rows) == 1
