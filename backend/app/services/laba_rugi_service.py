"""Laporan laba rugi (IMOGI no. 69): penjualan dan HPP dari transaksi selesai, biaya dari pengeluaran."""

import uuid
from datetime import datetime, timedelta
from decimal import Decimal

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.pengeluaran import Pengeluaran
from app.schemas.laporan import BiayaKategoriOut, LabaRugiOut
from app.services.laporan_service import _item_untuk_transaksi, _transaksi_selesai

# Belanja bahan sudah tercermin di HPP penjualan; tidak dikurangkan dua kali.
_KATEGORI_HPP = "belanja_bahan"


async def laba_rugi(
    db: AsyncSession, *, toko_id: uuid.UUID, outlet_id: uuid.UUID | None, dari: datetime, sampai: datetime
) -> LabaRugiOut:
    transaksi = await _transaksi_selesai(db, toko_id, outlet_id, dari, sampai)
    items = await _item_untuk_transaksi(db, [t.id for t in transaksi])

    nol = Decimal("0")
    penjualan_kotor = sum((Decimal(t.subtotal) for t in transaksi), nol)
    diskon = sum((Decimal(t.total_diskon) for t in transaksi), nol)
    penjualan_bersih = penjualan_kotor - diskon
    pajak = sum((Decimal(t.total_pajak) for t in transaksi), nol)
    hpp = sum((Decimal(i.hpp_satuan) * Decimal(i.qty) for i in items), nol)
    laba_kotor = penjualan_bersih - hpp

    # Pengeluaran dicatat per tanggal (tanpa jam): ambil tanggal dari [dari, sampai).
    tgl_awal = dari.date()
    tgl_akhir = (sampai - timedelta(microseconds=1)).date()
    query = select(Pengeluaran).where(
        Pengeluaran.toko_id == toko_id,
        Pengeluaran.deleted_at.is_(None),
        Pengeluaran.tanggal >= tgl_awal,
        Pengeluaran.tanggal <= tgl_akhir,
    )
    if outlet_id is not None:
        query = query.where(Pengeluaran.outlet_id == outlet_id)
    baris = (await db.execute(query)).scalars().all()

    per_kategori: dict[str, Decimal] = {}
    belanja_bahan = nol
    for b in baris:
        jumlah = Decimal(b.jumlah)
        if b.kategori == _KATEGORI_HPP:
            belanja_bahan += jumlah
        else:
            per_kategori[b.kategori] = per_kategori.get(b.kategori, nol) + jumlah
    total_biaya = sum(per_kategori.values(), nol)

    return LabaRugiOut(
        penjualan_kotor=penjualan_kotor,
        diskon=diskon,
        penjualan_bersih=penjualan_bersih,
        hpp=hpp,
        laba_kotor=laba_kotor,
        biaya_operasional=[
            BiayaKategoriOut(kategori=k, total=v) for k, v in sorted(per_kategori.items(), key=lambda kv: -kv[1])
        ],
        total_biaya_operasional=total_biaya,
        laba_bersih=laba_kotor - total_biaya,
        belanja_bahan=belanja_bahan,
        pajak_dipungut=pajak,
        jumlah_transaksi=len(transaksi),
    )
