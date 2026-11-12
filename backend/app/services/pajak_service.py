"""Rekap pajak (IMOGI no. 73) dan estimasi PPh Final UMKM (IMOGI no. 70) dari transaksi selesai."""

import uuid
from datetime import datetime
from decimal import ROUND_HALF_UP, Decimal

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.promo import Pajak
from app.models.transaksi import TransaksiPajak
from app.schemas.laporan import PphFinalBulanOut, PphFinalOut, RekapPajakBarisOut, RekapPajakOut
from app.services.laporan_service import _transaksi_selesai

TARIF_PPH_FINAL = Decimal("0.5")  # persen dari peredaran bruto (PP 55/2022 untuk UMKM)
_SEN = Decimal("0.01")


async def rekap_pajak(
    db: AsyncSession, *, toko_id: uuid.UUID, outlet_id: uuid.UUID | None, dari: datetime, sampai: datetime
) -> RekapPajakOut:
    transaksi = await _transaksi_selesai(db, toko_id, outlet_id, dari, sampai)
    ids = [t.id for t in transaksi]
    nol = Decimal("0")
    if not ids:
        return RekapPajakOut(baris=[], total_pajak=nol, total_service=nol, jumlah_transaksi=0)

    rows = (
        await db.execute(
            select(TransaksiPajak, Pajak.tipe)
            .outerjoin(Pajak, Pajak.id == TransaksiPajak.pajak_id)
            .where(TransaksiPajak.transaksi_id.in_(ids))
        )
    ).all()

    kelompok: dict[tuple[str, str, Decimal], dict] = {}
    for tp, tipe in rows:
        # Pajak yang sudah dihapus/ditautkan kosong dianggap pajak biasa, kecuali namanya Service.
        jenis = tipe or ("service" if tp.nama.strip().lower().startswith("service") else "pajak")
        kunci = (tp.nama, jenis, Decimal(tp.persen))
        g = kelompok.setdefault(kunci, {"transaksi": set(), "total": nol})
        g["transaksi"].add(tp.transaksi_id)
        g["total"] += Decimal(tp.jumlah)

    baris = sorted(
        (
            RekapPajakBarisOut(
                nama=nama, tipe=jenis, persen=persen, jumlah_transaksi=len(g["transaksi"]), total=g["total"]
            )
            for (nama, jenis, persen), g in kelompok.items()
        ),
        key=lambda b: (-b.total, b.nama),
    )
    return RekapPajakOut(
        baris=baris,
        total_pajak=sum((b.total for b in baris if b.tipe != "service"), nol),
        total_service=sum((b.total for b in baris if b.tipe == "service"), nol),
        jumlah_transaksi=len(transaksi),
    )


async def pph_final(
    db: AsyncSession, *, toko_id: uuid.UUID, outlet_id: uuid.UUID | None, dari: datetime, sampai: datetime
) -> PphFinalOut:
    transaksi = await _transaksi_selesai(db, toko_id, outlet_id, dari, sampai)
    nol = Decimal("0")
    per_bulan: dict[str, Decimal] = {}
    for t in transaksi:
        # Bulan menurut zona waktu rentang yang diminta (bukan UTC) agar sesuai bulan lokal toko.
        waktu = t.tanggal.astimezone(dari.tzinfo) if dari.tzinfo is not None else t.tanggal
        kunci = f"{waktu.year:04d}-{waktu.month:02d}"
        # Peredaran bruto: penjualan sebelum pajak/service yang dipungut (subtotal dikurangi diskon).
        per_bulan[kunci] = per_bulan.get(kunci, nol) + Decimal(t.subtotal) - Decimal(t.total_diskon)

    def hitung(omzet: Decimal) -> Decimal:
        return (omzet * TARIF_PPH_FINAL / Decimal(100)).quantize(_SEN, rounding=ROUND_HALF_UP)

    bulan = [PphFinalBulanOut(bulan=k, omzet=v, pph=hitung(v)) for k, v in sorted(per_bulan.items())]
    omzet = sum(per_bulan.values(), nol)
    return PphFinalOut(
        tarif_persen=TARIF_PPH_FINAL, omzet=omzet, pph_terutang=hitung(omzet), per_bulan=bulan
    )
