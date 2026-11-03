"""Logika rekonsiliasi kas shift - dipisah dari router supaya mudah dites
langsung (aturan dokumen #10: unit test wajib untuk hitungan selisih kas)."""

import uuid
from decimal import Decimal

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.transaksi import KasShift, MetodeBayar, Pembayaran, Refund


async def hitung_kas_seharusnya(db: AsyncSession, shift_id: uuid.UUID, modal_awal: Decimal) -> Decimal:
    """kas_seharusnya = modal_awal + tunai masuk dari penjualan + kas masuk
    manual - kas keluar manual - refund tunai. Hanya metode_bayar.masuk_laci
    =true yang dihitung (mis. tunai) - QRIS/kartu/transfer tidak pernah
    masuk laci fisik walau statusnya 'berhasil'.

    Tahap 3b-1 aturan #4: tunai masuk disaring lewat `Pembayaran.shift_id`
    LANGSUNG (shift TEMPAT uangnya diterima), bukan `Transaksi.shift_id`
    (shift transaksi aslinya dibuat) - supaya cicilan/pelunasan kasbon
    yang diterima di shift lain masuk kas shift PENERIMA, bukan shift
    transaksi awal. Refund tunai yang diproses di shift ini juga
    dikurangi dgn alasan simetris (`Refund.shift_id`)."""

    sum_tunai = await _sum_tunai_masuk(db, shift_id)
    sum_kas_masuk = await _sum_kas_shift(db, shift_id, "masuk")
    sum_kas_keluar = await _sum_kas_shift(db, shift_id, "keluar")
    sum_refund_tunai = await _sum_refund_tunai(db, shift_id)

    return modal_awal + sum_tunai + sum_kas_masuk - sum_kas_keluar - sum_refund_tunai


async def _sum_tunai_masuk(db: AsyncSession, shift_id: uuid.UUID) -> Decimal:
    total = await db.scalar(
        select(func.coalesce(func.sum(Pembayaran.jumlah), 0))
        .join(MetodeBayar, MetodeBayar.id == Pembayaran.metode_bayar_id)
        .where(
            Pembayaran.shift_id == shift_id,
            MetodeBayar.masuk_laci.is_(True),
            Pembayaran.status == "berhasil",
        )
    )
    return Decimal(total or 0)


async def _sum_refund_tunai(db: AsyncSession, shift_id: uuid.UUID) -> Decimal:
    total = await db.scalar(
        select(func.coalesce(func.sum(Refund.total), 0))
        .join(MetodeBayar, MetodeBayar.id == Refund.metode_bayar_id)
        .where(
            Refund.shift_id == shift_id,
            MetodeBayar.masuk_laci.is_(True),
        )
    )
    return Decimal(total or 0)


async def _sum_kas_shift(db: AsyncSession, shift_id: uuid.UUID, jenis: str) -> Decimal:
    total = await db.scalar(
        select(func.coalesce(func.sum(KasShift.jumlah), 0)).where(
            KasShift.shift_id == shift_id, KasShift.jenis == jenis, KasShift.deleted_at.is_(None)
        )
    )
    return Decimal(total or 0)
