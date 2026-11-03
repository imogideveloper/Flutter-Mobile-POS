"""Temuan A.1 (tahap 5) - penanda QRIS statis/manual dari HP tersimpan di
pembayaran.payload_gateway (CheckoutIn non-split, SplitPembayaranLineIn,
PembayaranPushIn kasbon), dan tampil terpisah di laporan sbg
'QRIS manual (belum terverifikasi)'."""

import uuid
from datetime import UTC, datetime
from decimal import Decimal

from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.transaksi import Pembayaran
from tests.conftest import buat_metode_bayar, buat_produk, buat_toko_siap_pakai

_MARKER = {"metode": "qris_statis_manual", "dikonfirmasi_kasir": True}


async def test_checkout_nonsplit_payload_gateway_tersimpan(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id, harga_jual=Decimal("15000"))
    metode_qris = await buat_metode_bayar(db_session, toko_a.toko.id, tipe="qris")

    resp = await client.post(
        "/transaksi",
        headers=toko_a.headers,
        json={
            "outlet_id": str(toko_a.outlet.id),
            "nomor_struk": "QRIS-1",
            "tanggal": datetime.now(UTC).isoformat(),
            "items": [
                {"produk_id": str(produk.id), "nama_produk": produk.nama, "qty": "1", "harga_satuan": "15000"}
            ],
            "metode_bayar_id": str(metode_qris.id),
            "total_bayar": "15000",
            "payload_gateway": _MARKER,
        },
    )
    assert resp.status_code == 201, resp.text
    pembayaran = (
        await db_session.execute(
            select(Pembayaran).where(Pembayaran.transaksi_id == uuid.UUID(resp.json()["id"]))
        )
    ).scalar_one()
    assert pembayaran.payload_gateway == _MARKER


async def test_checkout_split_payload_gateway_tersimpan(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id, harga_jual=Decimal("15000"))
    metode_qris = await buat_metode_bayar(db_session, toko_a.toko.id, tipe="qris")

    resp = await client.post(
        "/transaksi",
        headers=toko_a.headers,
        json={
            "outlet_id": str(toko_a.outlet.id),
            "nomor_struk": "QRIS-2",
            "tanggal": datetime.now(UTC).isoformat(),
            "items": [
                {"produk_id": str(produk.id), "nama_produk": produk.nama, "qty": "1", "harga_satuan": "15000"}
            ],
            "metode_bayar_id": str(metode_qris.id),
            "total_bayar": "15000",
            "split_pembayaran": [
                {"metode_bayar_id": str(metode_qris.id), "jumlah": "15000", "payload_gateway": _MARKER},
            ],
        },
    )
    assert resp.status_code == 201, resp.text
    pembayaran = (
        await db_session.execute(
            select(Pembayaran).where(Pembayaran.transaksi_id == uuid.UUID(resp.json()["id"]))
        )
    ).scalar_one()
    assert pembayaran.payload_gateway == _MARKER


async def test_pelunasan_kasbon_payload_gateway_tersimpan(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")  # fitur 'kasbon' butuh paket Pro+
    produk = await buat_produk(db_session, toko.toko.id, harga_jual=Decimal("50000"))
    metode_tunai = await buat_metode_bayar(db_session, toko.toko.id)
    metode_qris = await buat_metode_bayar(db_session, toko.toko.id, tipe="qris")

    shift_resp = await client.post(
        "/shift/buka", headers=toko.headers, json={"outlet_id": str(toko.outlet.id), "modal_awal": "0"}
    )
    shift_id = shift_resp.json()["id"]

    pelanggan_resp = await client.post("/pelanggan", headers=toko.headers, json={"nama": "Budi"})
    pelanggan_id = pelanggan_resp.json()["id"]

    checkout_resp = await client.post(
        "/transaksi",
        headers=toko.headers,
        json={
            "outlet_id": str(toko.outlet.id),
            "shift_id": shift_id,
            "pelanggan_id": pelanggan_id,
            "nomor_struk": "KASBON-QRIS-1",
            "tanggal": datetime.now(UTC).isoformat(),
            "items": [
                {"produk_id": str(produk.id), "nama_produk": produk.nama, "qty": "1", "harga_satuan": "50000"}
            ],
            "metode_bayar_id": str(metode_tunai.id),
            "total_bayar": "0",
        },
    )
    assert checkout_resp.status_code == 201, checkout_resp.text
    transaksi_id = checkout_resp.json()["id"]

    resp = await client.post(
        f"/transaksi/{transaksi_id}/pembayaran",
        headers=toko.headers,
        json={
            "shift_id": shift_id,
            "metode_bayar_id": str(metode_qris.id),
            "jumlah": "50000",
            "payload_gateway": _MARKER,
        },
    )
    assert resp.status_code == 201, resp.text
    pembayaran = await db_session.get(Pembayaran, uuid.UUID(resp.json()["id"]))
    assert pembayaran.payload_gateway == _MARKER


async def test_laporan_memisahkan_qris_manual_dari_qris_terverifikasi(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id, harga_jual=Decimal("20000"))
    metode_qris = await buat_metode_bayar(db_session, toko_a.toko.id, tipe="qris")

    # Transaksi 1: QRIS manual (ada marker).
    resp1 = await client.post(
        "/transaksi",
        headers=toko_a.headers,
        json={
            "outlet_id": str(toko_a.outlet.id),
            "nomor_struk": "QRIS-MANUAL-1",
            "tanggal": datetime.now(UTC).isoformat(),
            "items": [
                {"produk_id": str(produk.id), "nama_produk": produk.nama, "qty": "1", "harga_satuan": "20000"}
            ],
            "metode_bayar_id": str(metode_qris.id),
            "total_bayar": "20000",
            "payload_gateway": _MARKER,
        },
    )
    assert resp1.status_code == 201

    # Transaksi 2: QRIS "biasa" (tanpa marker manual - seandainya nanti ada
    # gateway sungguhan, payload_gateway-nya beda bentuk/kosong).
    resp2 = await client.post(
        "/transaksi",
        headers=toko_a.headers,
        json={
            "outlet_id": str(toko_a.outlet.id),
            "nomor_struk": "QRIS-VERIFIED-1",
            "tanggal": datetime.now(UTC).isoformat(),
            "items": [
                {"produk_id": str(produk.id), "nama_produk": produk.nama, "qty": "1", "harga_satuan": "20000"}
            ],
            "metode_bayar_id": str(metode_qris.id),
            "total_bayar": "20000",
        },
    )
    assert resp2.status_code == 201

    sekarang = datetime.now(UTC)
    resp = await client.get(
        "/laporan/penjualan",
        headers=toko_a.headers,
        params={
            "dari": sekarang.replace(hour=0, minute=0, second=0).isoformat(),
            "sampai": sekarang.isoformat(),
        },
    )
    assert resp.status_code == 200
    nama_metode = {m["nama"] for m in resp.json()["metode_bayar"]}
    assert "QRIS manual (belum terverifikasi)" in nama_metode
    assert "Qris" in nama_metode  # label metode "biasa" (buat_metode_bayar nama=tipe.capitalize())
