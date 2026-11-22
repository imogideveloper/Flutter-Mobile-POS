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
    masuk laci fisik walau statusnya 'berhasil'. Refund tunai: lihat `_sum_refund_tunai`.

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
    """Uang tunai yang keluar dari laci karena refund yang diproses di shift ini (AT2, docs/perlu_konfirmasi.md).

    - Nominal yang dihitung = `Refund.kas_dikembalikan` (uang yang BENAR2 keluar), bukan `total`: refund transaksi
      kasbon yang belum lunas dulu mengurangi sisa tagihan, hanya sisanya yang dikembalikan sebagai uang.
    - Metode refund dipilih kasir (`metode_bayar_id` terisi): tunai bila metode itu `masuk_laci`, selain itu 0.
    - Refund "Sama seperti transaksi asal" (`metode_bayar_id` kosong, yang dikirim aplikasi): bagian tunainya =
      porsi pembayaran tunai pada transaksi asal (bayar campur dibagi proporsional; keputusan sementara)."""

    refunds = (
        await db.execute(
            select(Refund).where(Refund.shift_id == shift_id, Refund.deleted_at.is_(None))
        )
    ).scalars().all()
    if not refunds:
        return Decimal("0")

    metode_laci = {
        mid: laci
        for mid, laci in (
            await db.execute(
                select(MetodeBayar.id, MetodeBayar.masuk_laci).where(
                    MetodeBayar.id.in_({r.metode_bayar_id for r in refunds if r.metode_bayar_id is not None})
                )
            )
        ).all()
    }

    # Porsi tunai pembayaran asal, hanya untuk refund tanpa metode eksplisit.
    transaksi_tanpa_metode = {r.transaksi_id for r in refunds if r.metode_bayar_id is None}
    porsi_tunai: dict[uuid.UUID, Decimal] = {}
    if transaksi_tanpa_metode:
        rows = await db.execute(
            select(Pembayaran.transaksi_id, MetodeBayar.masuk_laci, func.coalesce(func.sum(Pembayaran.jumlah), 0))
            .join(MetodeBayar, MetodeBayar.id == Pembayaran.metode_bayar_id)
            .where(Pembayaran.transaksi_id.in_(transaksi_tanpa_metode), Pembayaran.status == "berhasil")
            .group_by(Pembayaran.transaksi_id, MetodeBayar.masuk_laci)
        )
        tunai: dict[uuid.UUID, Decimal] = {}
        semua: dict[uuid.UUID, Decimal] = {}
        for transaksi_id, masuk_laci, jumlah in rows.all():
            jumlah = Decimal(str(jumlah))
            semua[transaksi_id] = semua.get(transaksi_id, Decimal("0")) + jumlah
            if masuk_laci:
                tunai[transaksi_id] = tunai.get(transaksi_id, Decimal("0")) + jumlah
        porsi_tunai = {
            tid: (tunai.get(tid, Decimal("0")) / total) if total > 0 else Decimal("0") for tid, total in semua.items()
        }

    total_tunai = Decimal("0")
    for r in refunds:
        keluar = Decimal(str(r.kas_dikembalikan or 0))
        if r.metode_bayar_id is not None:
            if metode_laci.get(r.metode_bayar_id):
                total_tunai += keluar
        else:
            total_tunai += keluar * porsi_tunai.get(r.transaksi_id, Decimal("0"))
    return total_tunai.quantize(Decimal("0.01"))


async def _sum_kas_shift(db: AsyncSession, shift_id: uuid.UUID, jenis: str) -> Decimal:
    total = await db.scalar(
        select(func.coalesce(func.sum(KasShift.jumlah), 0)).where(
            KasShift.shift_id == shift_id, KasShift.jenis == jenis, KasShift.deleted_at.is_(None)
        )
    )
    return Decimal(total or 0)
