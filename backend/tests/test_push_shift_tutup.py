"""Shift yang dibuat dan ditutup di HP ikut terkirim, dan transaksinya diterima walau shift sudah tutup."""

import uuid
from datetime import UTC, datetime
from decimal import Decimal

from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.transaksi import Shift, Transaksi
from tests.conftest import buat_metode_bayar, buat_perangkat, buat_produk


async def test_shift_tutup_dan_transaksinya_diterima_serta_kas_dihitung_ulang(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id)
    metode = await buat_metode_bayar(db_session, toko_a.toko.id)
    perangkat = await buat_perangkat(db_session, toko_a.toko.id, toko_a.outlet.id)
    shift_id, transaksi_id = str(uuid.uuid4()), str(uuid.uuid4())
    sekarang = datetime.now(UTC).isoformat()

    resp = await client.post(
        "/sync/push",
        headers=toko_a.headers,
        json={
            "perangkat_id": str(perangkat.id),
            "shift": [
                {
                    "id": shift_id,
                    "outlet_id": str(toko_a.outlet.id),
                    "dibuka_pada": sekarang,
                    "ditutup_pada": sekarang,
                    "modal_awal": "100000",
                    "kas_aktual": "115000",
                    "status": "tutup",
                }
            ],
            "transaksi": [
                {
                    "id": transaksi_id,
                    "outlet_id": str(toko_a.outlet.id),
                    "shift_id": shift_id,
                    "nomor_struk": "OUT1-SHIFT-0001",
                    "tanggal": sekarang,
                    "items": [
                        {"produk_id": str(produk.id), "nama_produk": produk.nama, "qty": "1", "harga_satuan": "15000"}
                    ],
                    "metode_bayar_id": str(metode.id),
                    "total_bayar": "15000",
                }
            ],
        },
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["shift"][0]["status"] == "diterima"
    assert body["transaksi"][0]["status"] == "diterima", body["transaksi"][0]

    shift = (await db_session.execute(select(Shift).where(Shift.id == uuid.UUID(shift_id)))).scalar_one()
    await db_session.refresh(shift)
    assert shift.status == "tutup"
    assert shift.kas_seharusnya == Decimal("115000"), "modal 100.000 + penjualan tunai 15.000, dihitung SETELAH transaksi masuk"
    assert shift.selisih == Decimal("0")
    assert (await db_session.execute(select(Transaksi).where(Transaksi.id == uuid.UUID(transaksi_id)))).scalar_one()


async def test_push_offline_dengan_pelanggan_yang_tidak_ada_di_server_tetap_diterima(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id)
    metode = await buat_metode_bayar(db_session, toko_a.toko.id)
    perangkat = await buat_perangkat(db_session, toko_a.toko.id, toko_a.outlet.id)
    transaksi_id = str(uuid.uuid4())

    resp = await client.post(
        "/sync/push",
        headers=toko_a.headers,
        json={
            "perangkat_id": str(perangkat.id),
            "transaksi": [
                {
                    "id": transaksi_id,
                    "outlet_id": str(toko_a.outlet.id),
                    "pelanggan_id": str(uuid.uuid4()),
                    "nomor_struk": "OUT1-PLG-0001",
                    "tanggal": datetime.now(UTC).isoformat(),
                    "items": [
                        {"produk_id": str(produk.id), "nama_produk": produk.nama, "qty": "1", "harga_satuan": "15000"}
                    ],
                    "metode_bayar_id": str(metode.id),
                    "total_bayar": "15000",
                }
            ],
        },
    )
    assert resp.json()["transaksi"][0]["status"] == "diterima"
    row = (await db_session.execute(select(Transaksi).where(Transaksi.id == uuid.UUID(transaksi_id)))).scalar_one()
    assert row.pelanggan_id is None
