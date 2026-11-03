from datetime import date
from decimal import Decimal

from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.stok import MutasiStok, Stok
from tests.conftest import buat_produk


async def test_buat_pembelian_lalu_terima_mendebet_stok_masuk(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    beras = await buat_produk(db_session, toko_a.toko.id, nama="Beras 5kg", harga_jual=Decimal("65000"))

    resp = await client.post(
        "/pembelian",
        headers=toko_a.headers,
        json={
            "outlet_id": str(toko_a.outlet.id),
            "nomor": "PO-0001",
            "tanggal": date.today().isoformat(),
            "items": [{"produk_id": str(beras.id), "qty": "10", "harga_satuan": "50000"}],
        },
    )
    assert resp.status_code == 201
    body = resp.json()
    assert body["status"] == "draft"
    assert body["subtotal"] == "500000"
    pembelian_id = body["id"]

    # Belum diterima - stok belum berubah sama sekali.
    stok_sebelum = (await db_session.execute(select(Stok).where(Stok.produk_id == beras.id))).scalar_one_or_none()
    assert stok_sebelum is None

    resp_terima = await client.post(f"/pembelian/{pembelian_id}/terima", headers=toko_a.headers)
    assert resp_terima.status_code == 200
    assert resp_terima.json()["status"] == "diterima"

    stok = (await db_session.execute(select(Stok).where(Stok.produk_id == beras.id))).scalar_one()
    assert stok.jumlah == Decimal("10")

    await db_session.refresh(beras)
    assert beras.hpp == Decimal("50000")


async def test_terima_pembelian_dua_kali_ditolak(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id)
    resp = await client.post(
        "/pembelian",
        headers=toko_a.headers,
        json={
            "outlet_id": str(toko_a.outlet.id),
            "nomor": "PO-0002",
            "tanggal": date.today().isoformat(),
            "items": [{"produk_id": str(produk.id), "qty": "5", "harga_satuan": "10000"}],
        },
    )
    pembelian_id = resp.json()["id"]

    await client.post(f"/pembelian/{pembelian_id}/terima", headers=toko_a.headers)
    resp2 = await client.post(f"/pembelian/{pembelian_id}/terima", headers=toko_a.headers)
    assert resp2.status_code == 409


async def test_pembelian_toko_lain_tidak_terlihat(client: AsyncClient, toko_a, toko_b) -> None:
    resp = await client.get("/pembelian", headers=toko_a.headers)
    assert resp.json() == []

    resp_supplier = await client.post(
        "/supplier", headers=toko_a.headers, json={"nama": "CV Sumber Pangan"}
    )
    assert resp_supplier.status_code == 201

    daftar_supplier_b = await client.get("/supplier", headers=toko_b.headers)
    assert daftar_supplier_b.json() == []


async def test_mutasi_stok_pembelian_tercatat(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id)
    resp = await client.post(
        "/pembelian",
        headers=toko_a.headers,
        json={
            "outlet_id": str(toko_a.outlet.id),
            "nomor": "PO-0003",
            "tanggal": date.today().isoformat(),
            "items": [{"produk_id": str(produk.id), "qty": "3", "harga_satuan": "10000"}],
        },
    )
    pembelian_id = resp.json()["id"]
    await client.post(f"/pembelian/{pembelian_id}/terima", headers=toko_a.headers)

    mutasi = (
        await db_session.execute(select(MutasiStok).where(MutasiStok.jenis == "pembelian"))
    ).scalars().all()
    assert len(mutasi) == 1
    assert mutasi[0].qty == Decimal("3")
