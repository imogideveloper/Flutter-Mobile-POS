"""Modul 4 (pembelian) - pembelian HANYA disimpan di server (aturan
dokumen #4.1, bukan modul lokal HP). Status draft/dipesan dulu dibuat
tanpa menyentuh stok sama sekali - stok masuk BARU terjadi saat status
berpindah ke 'diterima' (barang benar2 sudah sampai di outlet), via
`terima_pembelian`."""

import uuid
from decimal import ROUND_HALF_UP, Decimal

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.deps import require_outlet_access
from app.models.produk import Produk
from app.models.stok import ItemPembelian, Pembelian, Supplier
from app.schemas.pembelian import ItemPembelianOut, PembelianIn, PembelianOut
from app.services.kepemilikan import get_outlet_milik_toko, pastikan_produk_milik_toko
from app.services.stok_service import catat_mutasi


def _bulatkan(nilai: Decimal) -> Decimal:
    return nilai.quantize(Decimal("1"), rounding=ROUND_HALF_UP)


async def buat_pembelian(
    db: AsyncSession, *, toko_id: uuid.UUID, pengguna_id: uuid.UUID, role_id: uuid.UUID, body: PembelianIn
) -> PembelianOut:
    if not body.items:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Minimal satu item pembelian")

    await get_outlet_milik_toko(db, body.outlet_id, toko_id)
    await require_outlet_access(db, pengguna_id=pengguna_id, role_id=role_id, outlet_id=body.outlet_id)

    if body.supplier_id is not None:
        supplier = await db.get(Supplier, body.supplier_id)
        if supplier is None or supplier.toko_id != toko_id:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Supplier tidak ditemukan")

    produk_ids = {item.produk_id for item in body.items}
    varian_ids = {item.varian_id for item in body.items if item.varian_id is not None}
    await pastikan_produk_milik_toko(db, produk_ids, toko_id, varian_ids=varian_ids)

    subtotal = sum((_bulatkan(item.qty * item.harga_satuan) for item in body.items), Decimal("0"))

    pembelian = Pembelian(
        toko_id=toko_id,
        outlet_id=body.outlet_id,
        supplier_id=body.supplier_id,
        nomor=body.nomor,
        tanggal=body.tanggal,
        status="draft",
        subtotal=subtotal,
        total=subtotal,
        catatan=body.catatan,
        dibuat_oleh=pengguna_id,
    )
    db.add(pembelian)
    await db.flush()

    for item in body.items:
        db.add(
            ItemPembelian(
                pembelian_id=pembelian.id,
                produk_id=item.produk_id,
                varian_id=item.varian_id,
                qty=item.qty,
                harga_satuan=item.harga_satuan,
                subtotal=_bulatkan(item.qty * item.harga_satuan),
            )
        )

    await db.commit()
    return await pembelian_ke_out(db, pembelian)


async def terima_pembelian(db: AsyncSession, *, pembelian: Pembelian, pengguna_id: uuid.UUID) -> PembelianOut:
    if pembelian.status != "draft" and pembelian.status != "dipesan":
        raise HTTPException(
            status.HTTP_409_CONFLICT, "Hanya pembelian 'draft'/'dipesan' yang bisa ditandai diterima"
        )

    items = (
        await db.execute(select(ItemPembelian).where(ItemPembelian.pembelian_id == pembelian.id))
    ).scalars().all()

    for item in items:
        await catat_mutasi(
            db,
            toko_id=pembelian.toko_id,
            outlet_id=pembelian.outlet_id,
            produk_id=item.produk_id,
            varian_id=item.varian_id,
            jenis="pembelian",
            qty=item.qty,
            hpp_satuan=item.harga_satuan,
            ref_tipe="pembelian",
            ref_id=pembelian.id,
            dibuat_oleh=pengguna_id,
        )
        # Perbarui HPP produk jadi harga pembelian terakhir - penyederhanaan
        # dari "HPP rata-rata tertimbang" sungguhan (butuh saldo qty
        # sebelum+sesudah yang presisi, di luar scope minimal ini).
        produk = await db.get(Produk, item.produk_id)
        if produk is not None:
            produk.hpp = item.harga_satuan

    pembelian.status = "diterima"
    await db.commit()
    return await pembelian_ke_out(db, pembelian)


async def pembelian_ke_out(db: AsyncSession, pembelian: Pembelian) -> PembelianOut:
    rows = (
        await db.execute(
            select(ItemPembelian, Produk)
            .join(Produk, Produk.id == ItemPembelian.produk_id)
            .where(ItemPembelian.pembelian_id == pembelian.id)
        )
    ).all()
    return PembelianOut(
        id=pembelian.id,
        outlet_id=pembelian.outlet_id,
        supplier_id=pembelian.supplier_id,
        nomor=pembelian.nomor,
        tanggal=pembelian.tanggal,
        status=pembelian.status,
        subtotal=pembelian.subtotal,
        total=pembelian.total,
        status_bayar=pembelian.status_bayar,
        items=[
            ItemPembelianOut(
                id=item.id, produk_id=item.produk_id, nama_produk=produk.nama, varian_id=item.varian_id,
                qty=item.qty, harga_satuan=item.harga_satuan, subtotal=item.subtotal,
            )
            for item, produk in rows
        ],
    )
