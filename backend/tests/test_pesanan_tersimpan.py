"""F3.E - endpoint cadangan/backup 'pesanan tersimpan' (open bill). Lihat
docstring app/services/pesanan_tersimpan_service.py - ini SENGAJA bukan
sumber kebenaran yang bisa dilanjutkan dari HP lain, cuma backup."""

import uuid
from datetime import UTC, datetime
from decimal import Decimal

from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.transaksi import ItemTransaksi, Transaksi
from tests.conftest import buat_produk


async def test_simpan_pesanan_tidak_memotong_stok(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    from app.models.stok import Stok

    produk = await buat_produk(db_session, toko_a.toko.id, harga_jual=Decimal("15000"))
    pesanan_id = str(uuid.uuid4())

    resp = await client.post(
        "/transaksi/pesanan-tersimpan",
        headers=toko_a.headers,
        json={
            "id": pesanan_id,
            "outlet_id": str(toko_a.outlet.id),
            "nomor_struk": "DRAFT-1",
            "tanggal": datetime.now(UTC).isoformat(),
            "items": [
                {"produk_id": str(produk.id), "nama_produk": produk.nama, "qty": "2", "harga_satuan": "15000"}
            ],
        },
    )
    assert resp.status_code == 201
    body = resp.json()
    assert body["status"] == "tersimpan"
    assert Decimal(body["total"]) == 30000

    stok_rows = (await db_session.execute(select(Stok).where(Stok.produk_id == produk.id))).scalars().all()
    assert stok_rows == [], "pesanan tersimpan TIDAK BOLEH memotong stok"


async def test_simpan_pesanan_idempotent_menimpa_items_lama(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id, harga_jual=Decimal("15000"))
    pesanan_id = str(uuid.uuid4())
    payload = {
        "id": pesanan_id,
        "outlet_id": str(toko_a.outlet.id),
        "nomor_struk": "DRAFT-2",
        "tanggal": datetime.now(UTC).isoformat(),
        "items": [
            {"produk_id": str(produk.id), "nama_produk": produk.nama, "qty": "1", "harga_satuan": "15000"}
        ],
    }
    resp1 = await client.post("/transaksi/pesanan-tersimpan", headers=toko_a.headers, json=payload)
    assert resp1.status_code == 201

    payload["items"][0]["qty"] = "3"
    resp2 = await client.post("/transaksi/pesanan-tersimpan", headers=toko_a.headers, json=payload)
    assert resp2.status_code == 201
    assert Decimal(resp2.json()["total"]) == 45000

    items = (
        await db_session.execute(select(ItemTransaksi).where(ItemTransaksi.transaksi_id == uuid.UUID(pesanan_id)))
    ).scalars().all()
    assert len(items) == 1, "push ulang draft harus TIMPA item lama, bukan tumpuk baris baru"
    assert items[0].qty == Decimal("3")


async def test_hapus_pesanan_tersimpan(client: AsyncClient, db_session: AsyncSession, toko_a) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id, harga_jual=Decimal("15000"))
    pesanan_id = str(uuid.uuid4())
    await client.post(
        "/transaksi/pesanan-tersimpan",
        headers=toko_a.headers,
        json={
            "id": pesanan_id,
            "outlet_id": str(toko_a.outlet.id),
            "nomor_struk": "DRAFT-3",
            "tanggal": datetime.now(UTC).isoformat(),
            "items": [
                {"produk_id": str(produk.id), "nama_produk": produk.nama, "qty": "1", "harga_satuan": "15000"}
            ],
        },
    )

    resp = await client.delete(f"/transaksi/pesanan-tersimpan/{pesanan_id}", headers=toko_a.headers)
    assert resp.status_code == 204

    assert await db_session.get(Transaksi, uuid.UUID(pesanan_id)) is None

    # Idempotent - hapus lagi (sudah tidak ada) tetap 204, bukan error.
    resp2 = await client.delete(f"/transaksi/pesanan-tersimpan/{pesanan_id}", headers=toko_a.headers)
    assert resp2.status_code == 204


async def test_hapus_pesanan_milik_toko_lain_ditolak(
    client: AsyncClient, db_session: AsyncSession, toko_a, toko_b
) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id, harga_jual=Decimal("15000"))
    pesanan_id = str(uuid.uuid4())
    await client.post(
        "/transaksi/pesanan-tersimpan",
        headers=toko_a.headers,
        json={
            "id": pesanan_id,
            "outlet_id": str(toko_a.outlet.id),
            "nomor_struk": "DRAFT-4",
            "tanggal": datetime.now(UTC).isoformat(),
            "items": [
                {"produk_id": str(produk.id), "nama_produk": produk.nama, "qty": "1", "harga_satuan": "15000"}
            ],
        },
    )

    resp = await client.delete(f"/transaksi/pesanan-tersimpan/{pesanan_id}", headers=toko_b.headers)
    assert resp.status_code == 404

    assert await db_session.get(Transaksi, uuid.UUID(pesanan_id)) is not None, "harus tetap ada, tidak terhapus toko lain"
