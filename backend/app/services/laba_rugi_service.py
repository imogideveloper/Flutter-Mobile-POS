"""Laporan laba rugi (IMOGI no. 69): penjualan dan HPP dari transaksi selesai dan refund sebagian
(setelah dikurangi refund), biaya dari pengeluaran."""

import uuid
from datetime import datetime, timedelta
from decimal import Decimal

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.pengeluaran import Pengeluaran
from app.models.outlet import Outlet
from app.schemas.laporan import BiayaKategoriOut, LabaRugiKonsolidasiOut, LabaRugiOut, LabaRugiOutletOut
from app.services.laporan_service import _DUA_DESIMAL, item_penjualan, transaksi_penjualan

# Belanja bahan sudah tercermin di HPP penjualan; tidak dikurangkan dua kali.
_KATEGORI_HPP = "belanja_bahan"


async def laba_rugi(
    db: AsyncSession, *, toko_id: uuid.UUID, outlet_id: uuid.UUID | None, dari: datetime, sampai: datetime
) -> LabaRugiOut:
    # Transaksi selesai + refund sebagian; refund penuh dan void tidak ikut. Nilai tiap transaksi dikurangi
    # proporsional sebesar refund-nya (AT1). HPP hanya dikurangi untuk barang yang dikembalikan ke stok.
    penjualan = await transaksi_penjualan(db, toko_id, outlet_id, dari, sampai)
    items = await item_penjualan(db, [p.transaksi.id for p in penjualan])

    nol = Decimal("0")
    penjualan_kotor = sum((Decimal(p.transaksi.subtotal) * p.sisa for p in penjualan), nol).quantize(_DUA_DESIMAL)
    diskon = sum((Decimal(p.transaksi.total_diskon) * p.sisa for p in penjualan), nol).quantize(_DUA_DESIMAL)
    penjualan_bersih = penjualan_kotor - diskon
    pajak = sum((p.pajak_service for p in penjualan), nol)
    hpp = sum((Decimal(i.item.hpp_satuan) * i.qty_hpp for i in items), nol)
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
        jumlah_transaksi=len(penjualan),
    )


async def laba_rugi_konsolidasi(
    db: AsyncSession, *, toko_id: uuid.UUID, dari: datetime, sampai: datetime
) -> LabaRugiKonsolidasiOut:
    """Laba rugi per outlet aktif + total toko (IMOGI no. 84). Total dihitung langsung untuk seluruh toko
    (bukan penjumlahan baris), supaya biaya tanpa outlet dan outlet yang sudah dihapus tetap ikut."""
    outlets = (
        await db.execute(
            select(Outlet)
            .where(Outlet.toko_id == toko_id, Outlet.deleted_at.is_(None), Outlet.aktif.is_(True))
            .order_by(Outlet.created_at)
        )
    ).scalars().all()
    per_outlet = [
        LabaRugiOutletOut(
            outlet_id=o.id,
            outlet_nama=o.nama,
            laporan=await laba_rugi(db, toko_id=toko_id, outlet_id=o.id, dari=dari, sampai=sampai),
        )
        for o in outlets
    ]
    total = await laba_rugi(db, toko_id=toko_id, outlet_id=None, dari=dari, sampai=sampai)
    biaya_outlet = sum((Decimal(p.laporan.total_biaya_operasional) for p in per_outlet), Decimal("0"))
    return LabaRugiKonsolidasiOut(
        per_outlet=per_outlet,
        total=total,
        biaya_tanpa_outlet=Decimal(total.total_biaya_operasional) - biaya_outlet,
    )
