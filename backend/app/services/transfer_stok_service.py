"""Transfer stok antar outlet - HANYA di server (aturan dokumen #4.1).
Dua tahap: 'dikirim' (stok KELUAR di outlet asal, barang sudah lepas dari
sana) lalu 'diterima' (stok MASUK di outlet tujuan, baru stok tujuan
bertambah) - supaya ada jeda waktu (barang "di jalan") yang tidak
dobel-hitung di stok manapun, bukan transfer seketika."""

import uuid
from datetime import UTC, datetime

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.deps import require_outlet_access
from app.models.produk import Produk
from app.models.stok import ItemTransfer, TransferStok
from app.schemas.transfer_stok import ItemTransferOut, TransferStokIn, TransferStokOut
from app.services.kepemilikan import get_outlet_milik_toko, pastikan_produk_milik_toko
from app.services.stok_service import catat_mutasi


async def buat_transfer(
    db: AsyncSession, *, toko_id: uuid.UUID, pengguna_id: uuid.UUID, role_id: uuid.UUID, body: TransferStokIn
) -> TransferStokOut:
    if body.dari_outlet_id == body.ke_outlet_id:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Outlet asal dan tujuan tidak boleh sama")
    if not body.items:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Minimal satu item transfer")

    # Outlet asal DAN tujuan wajib milik toko yang sama (toko dari token) -
    # tanpa ini toko A bisa menebak outlet_id milik toko B dan mencuri
    # stok lintas-tenant lewat alur kirim/terima.
    await get_outlet_milik_toko(db, body.dari_outlet_id, toko_id)
    await get_outlet_milik_toko(db, body.ke_outlet_id, toko_id)
    # Hak akses outlet (Kasir dkk) HANYA dicek utk outlet ASAL - barang
    # keluar dari outlet jatahnya; outlet tujuan sengaja tidak dibatasi
    # sama (aturan tugas - transfer antar outlet toko yg sama memang wajar
    # dipicu dari outlet asal, tujuan diterima oleh kasir outlet lain).
    await require_outlet_access(db, pengguna_id=pengguna_id, role_id=role_id, outlet_id=body.dari_outlet_id)

    produk_ids = {item.produk_id for item in body.items}
    varian_ids = {item.varian_id for item in body.items if item.varian_id is not None}
    await pastikan_produk_milik_toko(db, produk_ids, toko_id, varian_ids=varian_ids)

    transfer = TransferStok(
        toko_id=toko_id,
        dari_outlet_id=body.dari_outlet_id,
        ke_outlet_id=body.ke_outlet_id,
        nomor=body.nomor,
        status="draft",
        dibuat_oleh=pengguna_id,
    )
    db.add(transfer)
    await db.flush()

    for item in body.items:
        db.add(
            ItemTransfer(
                transfer_stok_id=transfer.id, produk_id=item.produk_id, varian_id=item.varian_id, qty=item.qty
            )
        )

    await db.commit()
    return await transfer_ke_out(db, transfer)


async def kirim_transfer(db: AsyncSession, *, transfer: TransferStok, pengguna_id: uuid.UUID) -> TransferStokOut:
    if transfer.status != "draft":
        raise HTTPException(status.HTTP_409_CONFLICT, "Hanya transfer 'draft' yang bisa dikirim")

    items = (
        await db.execute(select(ItemTransfer).where(ItemTransfer.transfer_stok_id == transfer.id))
    ).scalars().all()

    for item in items:
        await catat_mutasi(
            db,
            toko_id=transfer.toko_id,
            outlet_id=transfer.dari_outlet_id,
            produk_id=item.produk_id,
            varian_id=item.varian_id,
            jenis="transfer_keluar",
            qty=-item.qty,
            ref_tipe="transfer_stok",
            ref_id=transfer.id,
            dibuat_oleh=pengguna_id,
        )

    transfer.status = "dikirim"
    transfer.dikirim_pada = datetime.now(UTC)
    await db.commit()
    return await transfer_ke_out(db, transfer)


async def terima_transfer(db: AsyncSession, *, transfer: TransferStok, pengguna_id: uuid.UUID) -> TransferStokOut:
    if transfer.status != "dikirim":
        raise HTTPException(status.HTTP_409_CONFLICT, "Hanya transfer 'dikirim' yang bisa ditandai diterima")

    items = (
        await db.execute(select(ItemTransfer).where(ItemTransfer.transfer_stok_id == transfer.id))
    ).scalars().all()

    for item in items:
        await catat_mutasi(
            db,
            toko_id=transfer.toko_id,
            outlet_id=transfer.ke_outlet_id,
            produk_id=item.produk_id,
            varian_id=item.varian_id,
            jenis="transfer_masuk",
            qty=item.qty,
            ref_tipe="transfer_stok",
            ref_id=transfer.id,
            dibuat_oleh=pengguna_id,
        )

    transfer.status = "diterima"
    transfer.diterima_pada = datetime.now(UTC)
    await db.commit()
    return await transfer_ke_out(db, transfer)


async def transfer_ke_out(db: AsyncSession, transfer: TransferStok) -> TransferStokOut:
    rows = (
        await db.execute(
            select(ItemTransfer, Produk)
            .join(Produk, Produk.id == ItemTransfer.produk_id)
            .where(ItemTransfer.transfer_stok_id == transfer.id)
        )
    ).all()
    return TransferStokOut(
        id=transfer.id,
        dari_outlet_id=transfer.dari_outlet_id,
        ke_outlet_id=transfer.ke_outlet_id,
        nomor=transfer.nomor,
        status=transfer.status,
        items=[
            ItemTransferOut(id=item.id, produk_id=item.produk_id, nama_produk=produk.nama, varian_id=item.varian_id, qty=item.qty)
            for item, produk in rows
        ],
    )
