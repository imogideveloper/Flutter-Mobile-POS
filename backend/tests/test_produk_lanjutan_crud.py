"""Tahap 5 B.6/B.8 - PATCH/DELETE varian, grup_modifier, modifier, resep,
bundling, harga_grosir, harga_outlet; CRUD produk_pajak (gate pajak_per_produk)."""

from decimal import Decimal

from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.audit import AuditLog
from app.models.produk import BundlingItem, GrupModifier, HargaGrosir, HargaOutlet, Modifier, ProdukVarian, Resep
from app.models.promo import Pajak
from tests.conftest import buat_produk, buat_toko_siap_pakai


async def test_varian_patch_delete(client: AsyncClient, db_session: AsyncSession, toko_a) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id)
    varian = ProdukVarian(produk_id=produk.id, nama="Besar", harga_jual=Decimal("20000"))
    db_session.add(varian)
    await db_session.commit()

    resp = await client.patch(
        f"/produk/{produk.id}/varian/{varian.id}", headers=toko_a.headers, json={"harga_jual": "25000"}
    )
    assert resp.status_code == 200
    assert Decimal(resp.json()["harga_jual"]) == Decimal("25000")

    resp2 = await client.delete(f"/produk/{produk.id}/varian/{varian.id}", headers=toko_a.headers)
    assert resp2.status_code == 204
    await db_session.refresh(varian)
    assert varian.deleted_at is not None

    audit_rows = (
        await db_session.execute(select(AuditLog).where(AuditLog.aksi.in_(["ubah_varian", "hapus_varian"])))
    ).scalars().all()
    assert len(audit_rows) == 2


async def test_grup_modifier_dan_modifier_patch_delete(client: AsyncClient, db_session: AsyncSession, toko_a) -> None:
    grup = GrupModifier(toko_id=toko_a.toko.id, nama="Topping")
    db_session.add(grup)
    await db_session.flush()
    modifier = Modifier(grup_modifier_id=grup.id, nama="Keju", harga_tambahan=Decimal("5000"))
    db_session.add(modifier)
    await db_session.commit()

    resp = await client.patch(f"/grup-modifier/{grup.id}", headers=toko_a.headers, json={"maks_pilih": 3})
    assert resp.status_code == 200
    assert resp.json()["maks_pilih"] == 3

    resp2 = await client.patch(
        f"/grup-modifier/{grup.id}/modifier/{modifier.id}", headers=toko_a.headers,
        json={"harga_tambahan": "7000"},
    )
    assert resp2.status_code == 200
    assert Decimal(resp2.json()["harga_tambahan"]) == Decimal("7000")

    resp3 = await client.delete(f"/grup-modifier/{grup.id}/modifier/{modifier.id}", headers=toko_a.headers)
    assert resp3.status_code == 204
    await db_session.refresh(modifier)
    assert modifier.deleted_at is not None

    resp4 = await client.delete(f"/grup-modifier/{grup.id}", headers=toko_a.headers)
    assert resp4.status_code == 204
    await db_session.refresh(grup)
    assert grup.deleted_at is not None


async def test_resep_patch_delete_digate_fitur(client: AsyncClient, db_session: AsyncSession) -> None:
    toko_gratis = await buat_toko_siap_pakai(db_session, nama_paket="Gratis")
    produk = await buat_produk(db_session, toko_gratis.toko.id)
    bahan = await buat_produk(db_session, toko_gratis.toko.id, nama="Bahan")
    resep = Resep(produk_id=produk.id, bahan_id=bahan.id, qty=Decimal("1"))
    db_session.add(resep)
    await db_session.commit()

    resp = await client.patch(
        f"/produk/{produk.id}/resep/{resep.id}", headers=toko_gratis.headers, json={"qty": "2"}
    )
    assert resp.status_code == 403
    assert resp.json()["detail"]["kode"] == "fitur_terkunci"


async def test_resep_patch_delete(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    produk = await buat_produk(db_session, toko.toko.id)
    bahan = await buat_produk(db_session, toko.toko.id, nama="Bahan")
    resep = Resep(produk_id=produk.id, bahan_id=bahan.id, qty=Decimal("1"))
    db_session.add(resep)
    await db_session.commit()

    resp = await client.patch(f"/produk/{produk.id}/resep/{resep.id}", headers=toko.headers, json={"qty": "2"})
    assert resp.status_code == 200
    assert Decimal(resp.json()["qty"]) == Decimal("2")

    resp2 = await client.delete(f"/produk/{produk.id}/resep/{resep.id}", headers=toko.headers)
    assert resp2.status_code == 204
    await db_session.refresh(resep)
    assert resep.deleted_at is not None


async def test_bundling_patch_delete(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    bundle = await buat_produk(db_session, toko.toko.id, nama="Paket Hemat")
    isi = await buat_produk(db_session, toko.toko.id, nama="Isi")
    item = BundlingItem(bundling_produk_id=bundle.id, produk_id=isi.id, qty=Decimal("1"))
    db_session.add(item)
    await db_session.commit()

    resp = await client.patch(
        f"/produk/{bundle.id}/bundling/{item.id}", headers=toko.headers, json={"qty": "3"}
    )
    assert resp.status_code == 200
    assert Decimal(resp.json()["qty"]) == Decimal("3")

    resp2 = await client.delete(f"/produk/{bundle.id}/bundling/{item.id}", headers=toko.headers)
    assert resp2.status_code == 204
    await db_session.refresh(item)
    assert item.deleted_at is not None


async def test_harga_grosir_patch_delete(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    produk = await buat_produk(db_session, toko.toko.id)
    harga = HargaGrosir(produk_id=produk.id, min_qty=Decimal("5"), harga=Decimal("12000"))
    db_session.add(harga)
    await db_session.commit()

    resp = await client.patch(
        f"/produk/{produk.id}/harga-grosir/{harga.id}", headers=toko.headers, json={"harga": "11000"}
    )
    assert resp.status_code == 200
    assert Decimal(resp.json()["harga"]) == Decimal("11000")

    resp2 = await client.delete(f"/produk/{produk.id}/harga-grosir/{harga.id}", headers=toko.headers)
    assert resp2.status_code == 204
    await db_session.refresh(harga)
    assert harga.deleted_at is not None


async def test_harga_outlet_patch_delete(client: AsyncClient, db_session: AsyncSession, toko_a) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id)
    harga = HargaOutlet(produk_id=produk.id, outlet_id=toko_a.outlet.id, harga_jual=Decimal("16000"))
    db_session.add(harga)
    await db_session.commit()

    resp = await client.patch(
        f"/produk/{produk.id}/harga-outlet/{harga.id}", headers=toko_a.headers, json={"harga_jual": "17000"}
    )
    assert resp.status_code == 200
    assert Decimal(resp.json()["harga_jual"]) == Decimal("17000")

    resp2 = await client.delete(f"/produk/{produk.id}/harga-outlet/{harga.id}", headers=toko_a.headers)
    assert resp2.status_code == 204
    await db_session.refresh(harga)
    assert harga.deleted_at is not None


async def test_produk_pajak_link_unlink_digate_fitur(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    produk = await buat_produk(db_session, toko.toko.id)
    pajak = Pajak(toko_id=toko.toko.id, nama="PB1", persen=Decimal("10"))
    db_session.add(pajak)
    await db_session.commit()

    resp = await client.post(f"/produk/{produk.id}/pajak/{pajak.id}", headers=toko.headers)
    assert resp.status_code == 204

    # Idempoten - panggil ulang tidak error/dobel baris.
    resp_dobel = await client.post(f"/produk/{produk.id}/pajak/{pajak.id}", headers=toko.headers)
    assert resp_dobel.status_code == 204

    resp2 = await client.get(f"/produk/{produk.id}/pajak", headers=toko.headers)
    assert resp2.status_code == 200
    assert len(resp2.json()) == 1
    assert resp2.json()[0]["nama_pajak"] == "PB1"

    resp3 = await client.delete(f"/produk/{produk.id}/pajak/{pajak.id}", headers=toko.headers)
    assert resp3.status_code == 204
    resp4 = await client.get(f"/produk/{produk.id}/pajak", headers=toko.headers)
    assert resp4.json() == []

    audit = (await db_session.execute(select(AuditLog).where(AuditLog.aksi == "lepas_produk_pajak"))).scalar_one()
    assert audit.data_lama["pajak_id"] == str(pajak.id)
