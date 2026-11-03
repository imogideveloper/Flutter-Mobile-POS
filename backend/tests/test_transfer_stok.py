from decimal import Decimal

from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.outlet import Outlet
from app.models.stok import Stok
from tests.conftest import buat_produk


async def _buat_outlet_kedua(db_session: AsyncSession, toko_id) -> Outlet:
    outlet = Outlet(toko_id=toko_id, kode="OUT2", nama="Outlet Cabang")
    db_session.add(outlet)
    await db_session.commit()
    await db_session.refresh(outlet)
    return outlet


async def test_transfer_dari_outlet_ke_outlet_sama_ditolak(client: AsyncClient, toko_a) -> None:
    resp = await client.post(
        "/transfer-stok",
        headers=toko_a.headers,
        json={
            "dari_outlet_id": str(toko_a.outlet.id),
            "ke_outlet_id": str(toko_a.outlet.id),
            "nomor": "TRF-0001",
            "items": [{"produk_id": "00000000-0000-0000-0000-000000000000", "qty": "1"}],
        },
    )
    assert resp.status_code == 400


async def test_transfer_kirim_lalu_terima_pindahkan_stok_antar_outlet(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    outlet_cabang = await _buat_outlet_kedua(db_session, toko_a.toko.id)
    produk = await buat_produk(db_session, toko_a.toko.id)

    # Isi stok awal di outlet pusat lewat stok opname (jalur resmi).
    await client.post(
        "/stok-opname",
        headers=toko_a.headers,
        json={
            "outlet_id": str(toko_a.outlet.id),
            "nomor": "OPN-SEED-001",
            "tanggal": "2026-01-01",
            "items": [{"produk_id": str(produk.id), "qty_fisik": "20"}],
        },
    )
    opname_id = (await client.get("/stok-opname", headers=toko_a.headers, params={"outlet_id": str(toko_a.outlet.id)})).json()[0]["id"]
    await client.post(f"/stok-opname/{opname_id}/selesai", headers=toko_a.headers)

    resp = await client.post(
        "/transfer-stok",
        headers=toko_a.headers,
        json={
            "dari_outlet_id": str(toko_a.outlet.id),
            "ke_outlet_id": str(outlet_cabang.id),
            "nomor": "TRF-0002",
            "items": [{"produk_id": str(produk.id), "qty": "5"}],
        },
    )
    assert resp.status_code == 201
    transfer_id = resp.json()["id"]
    assert resp.json()["status"] == "draft"

    resp_kirim = await client.post(f"/transfer-stok/{transfer_id}/kirim", headers=toko_a.headers)
    assert resp_kirim.status_code == 200
    assert resp_kirim.json()["status"] == "dikirim"

    stok_asal = (
        await db_session.execute(select(Stok).where(Stok.outlet_id == toko_a.outlet.id, Stok.produk_id == produk.id))
    ).scalar_one()
    assert stok_asal.jumlah == Decimal("15")  # 20 - 5, sudah keluar walau belum diterima

    stok_tujuan_sebelum = (
        await db_session.execute(select(Stok).where(Stok.outlet_id == outlet_cabang.id, Stok.produk_id == produk.id))
    ).scalar_one_or_none()
    assert stok_tujuan_sebelum is None  # belum nambah krn belum diterima

    resp_terima = await client.post(f"/transfer-stok/{transfer_id}/terima", headers=toko_a.headers)
    assert resp_terima.status_code == 200
    assert resp_terima.json()["status"] == "diterima"

    stok_tujuan = (
        await db_session.execute(select(Stok).where(Stok.outlet_id == outlet_cabang.id, Stok.produk_id == produk.id))
    ).scalar_one()
    assert stok_tujuan.jumlah == Decimal("5")


async def test_terima_transfer_sebelum_dikirim_ditolak(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    outlet_cabang = await _buat_outlet_kedua(db_session, toko_a.toko.id)
    produk = await buat_produk(db_session, toko_a.toko.id)

    resp = await client.post(
        "/transfer-stok",
        headers=toko_a.headers,
        json={
            "dari_outlet_id": str(toko_a.outlet.id),
            "ke_outlet_id": str(outlet_cabang.id),
            "nomor": "TRF-0003",
            "items": [{"produk_id": str(produk.id), "qty": "1"}],
        },
    )
    transfer_id = resp.json()["id"]

    resp_terima = await client.post(f"/transfer-stok/{transfer_id}/terima", headers=toko_a.headers)
    assert resp_terima.status_code == 409
