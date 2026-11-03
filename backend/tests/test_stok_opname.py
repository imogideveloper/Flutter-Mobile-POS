from datetime import date
from decimal import Decimal

from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.stok import MutasiStok, Stok
from tests.conftest import buat_produk


async def test_opname_snapshot_qty_sistem_dan_hitung_selisih(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id)
    # Belum ada baris stok sama sekali - qty_sistem harus 0.

    resp = await client.post(
        "/stok-opname",
        headers=toko_a.headers,
        json={
            "outlet_id": str(toko_a.outlet.id),
            "nomor": "OPN-0001",
            "tanggal": date.today().isoformat(),
            "items": [{"produk_id": str(produk.id), "qty_fisik": "8"}],
        },
    )
    assert resp.status_code == 201
    body = resp.json()
    assert body["status"] == "draft"
    item = body["items"][0]
    assert item["qty_sistem"] == "0.0000"
    assert item["qty_fisik"] == "8.0000"
    assert item["selisih"] == "8.0000"


async def test_selesaikan_opname_menyesuaikan_stok_dan_catat_mutasi(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id)

    resp = await client.post(
        "/stok-opname",
        headers=toko_a.headers,
        json={
            "outlet_id": str(toko_a.outlet.id),
            "nomor": "OPN-0002",
            "tanggal": date.today().isoformat(),
            "items": [{"produk_id": str(produk.id), "qty_fisik": "8"}],
        },
    )
    opname_id = resp.json()["id"]

    resp_selesai = await client.post(f"/stok-opname/{opname_id}/selesai", headers=toko_a.headers)
    assert resp_selesai.status_code == 200
    assert resp_selesai.json()["status"] == "selesai"

    stok = (await db_session.execute(select(Stok).where(Stok.produk_id == produk.id))).scalar_one()
    assert stok.jumlah == Decimal("8")

    mutasi = (
        await db_session.execute(select(MutasiStok).where(MutasiStok.jenis == "opname"))
    ).scalars().all()
    assert len(mutasi) == 1
    assert mutasi[0].qty == Decimal("8")


async def test_opname_tanpa_selisih_tidak_bikin_mutasi(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id)

    resp = await client.post(
        "/stok-opname",
        headers=toko_a.headers,
        json={
            "outlet_id": str(toko_a.outlet.id),
            "nomor": "OPN-0003",
            "tanggal": date.today().isoformat(),
            "items": [{"produk_id": str(produk.id), "qty_fisik": "0"}],  # sama dgn qty_sistem (0)
        },
    )
    opname_id = resp.json()["id"]

    await client.post(f"/stok-opname/{opname_id}/selesai", headers=toko_a.headers)

    mutasi = (
        await db_session.execute(select(MutasiStok).where(MutasiStok.jenis == "opname"))
    ).scalars().all()
    assert mutasi == []


async def test_selesaikan_opname_dua_kali_ditolak(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id)
    resp = await client.post(
        "/stok-opname",
        headers=toko_a.headers,
        json={
            "outlet_id": str(toko_a.outlet.id),
            "nomor": "OPN-0004",
            "tanggal": date.today().isoformat(),
            "items": [{"produk_id": str(produk.id), "qty_fisik": "5"}],
        },
    )
    opname_id = resp.json()["id"]

    await client.post(f"/stok-opname/{opname_id}/selesai", headers=toko_a.headers)
    resp2 = await client.post(f"/stok-opname/{opname_id}/selesai", headers=toko_a.headers)
    assert resp2.status_code == 409


async def test_opname_outlet_toko_lain_ditolak(client: AsyncClient, toko_a, toko_b) -> None:
    resp = await client.post(
        "/stok-opname",
        headers=toko_b.headers,
        json={
            "outlet_id": str(toko_a.outlet.id),
            "nomor": "OPN-0005",
            "tanggal": date.today().isoformat(),
            "items": [{"produk_id": "00000000-0000-0000-0000-000000000000", "qty_fisik": "1"}],
        },
    )
    assert resp.status_code == 404
