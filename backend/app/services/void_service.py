"""Void transaksi: tandai status + balikkan stok yang sudah terdebet saat
checkout, dalam satu DB transaction. Pemanggil (router) WAJIB pastikan
izin/PIN approval sudah divalidasi SEBELUM memanggil ini - service ini
tidak mengecek otorisasi (sama pembagian tanggung jawab dengan versi
Flutter-nya, TransaksiRepository.voidTransaksi)."""

import uuid
from datetime import UTC, datetime

from fastapi import HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.transaksi import ItemTransaksi, Pembayaran, Transaksi
from app.services.loyalty_service import batalkan_poin_transaksi, kembalikan_poin_ditukar
from app.services.stok_service import catat_mutasi


async def void_transaksi(
    db: AsyncSession,
    *,
    transaksi: Transaksi,
    alasan: str,
    disetujui_oleh: uuid.UUID,
) -> Transaksi:
    if transaksi.status != "selesai":
        raise HTTPException(status.HTTP_409_CONFLICT, "Hanya transaksi 'selesai' yang bisa di-void")

    # Tahap 3b-1 aturan #5: void transaksi kasbon (jatuh_tempo not None -
    # pernah lewat jalur kasbon di checkout) hanya boleh kalau belum ada
    # pembayaran SAMA SEKALI (termasuk DP awal) - begitu ada uang yang
    # sudah diterima kasir, pembatalannya wajib lewat refund, bukan void
    # (refund tahu cara mengurangi sisa_tagihan dgn benar, void tidak).
    if transaksi.jatuh_tempo is not None:
        ada_pembayaran = await db.scalar(
            select(func.count()).select_from(Pembayaran).where(Pembayaran.transaksi_id == transaksi.id)
        )
        if ada_pembayaran:
            raise HTTPException(
                status.HTTP_409_CONFLICT,
                "Transaksi kasbon ini sudah ada pembayaran - pakai refund, bukan void",
            )

    items = (
        await db.execute(select(ItemTransaksi).where(ItemTransaksi.transaksi_id == transaksi.id))
    ).scalars().all()

    for item in items:
        await catat_mutasi(
            db,
            toko_id=transaksi.toko_id,
            outlet_id=transaksi.outlet_id,
            produk_id=item.produk_id,
            varian_id=item.varian_id,
            jenis="void",
            qty=item.qty,  # positif - mengembalikan stok yang terdebet saat checkout
            hpp_satuan=item.hpp_satuan,
            ref_tipe="transaksi",
            ref_id=transaksi.id,
            dibuat_oleh=disetujui_oleh,
        )

    await batalkan_poin_transaksi(
        db, pelanggan_id=transaksi.pelanggan_id, transaksi_id=transaksi.id, total=transaksi.total
    )
    await kembalikan_poin_ditukar(db, pelanggan_id=transaksi.pelanggan_id, transaksi_id=transaksi.id)

    transaksi.status = "void"
    transaksi.alasan_void = alasan
    transaksi.void_disetujui_oleh = disetujui_oleh
    transaksi.updated_at = datetime.now(UTC)

    await db.commit()
    await db.refresh(transaksi)
    return transaksi
