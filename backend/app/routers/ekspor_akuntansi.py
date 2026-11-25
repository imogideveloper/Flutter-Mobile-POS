"""Ekspor ringkasan harian untuk software akuntansi (IMOGI no. 85).

Berkas CSV netral (bisa dibuka di spreadsheet atau diimpor ke Jurnal/Accurate/Zahir setelah pemetaan akun oleh
akuntan): satu baris per tanggal x jenis x rincian. Kolom kode_akun dan nama_akun berisi akun USULAN dari bagan akun
standar (services/coa_standar.py, IMOGI no. 80); akuntan tetap bisa memetakan ulang."""

import csv
import io
import uuid
from datetime import UTC, date, datetime, time, timedelta
from decimal import Decimal

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_db
from app.core.deps import get_role_id, get_toko_id
from app.models.pengeluaran import Pengeluaran
from app.models.transaksi import MetodeBayar, Pembayaran, Transaksi
from app.services.coa_standar import akun_untuk_baris_ekspor
from app.services.fitur_service import require_fitur
from app.services.izin_service import has_izin
from app.services.laporan_service import _item_untuk_transaksi, _transaksi_selesai

router = APIRouter(
    prefix="/ekspor-akuntansi", tags=["ekspor-akuntansi"], dependencies=[Depends(require_fitur("accounting_export"))]
)

_MAKS_HARI = 93
KOLOM = ("tanggal", "jenis", "rincian", "jumlah", "kode_akun", "nama_akun")


class EksporOut(BaseModel):
    nama_berkas: str
    jumlah_baris: int
    csv: str


def susun_baris(
    transaksi: list[Transaksi],
    hpp_per_transaksi: dict[uuid.UUID, Decimal],
    pembayaran: list[tuple[date, str, Decimal]],
    biaya: list[tuple[date, str, Decimal]],
) -> list[tuple[str, str, str, Decimal]]:
    """Baris (tanggal, jenis, rincian, jumlah) terurut menurut tanggal lalu jenis. Murni, tanpa DB."""
    jumlah: dict[tuple[date, str, str], Decimal] = {}

    def tambah(tgl: date, jenis: str, rincian: str, nilai: Decimal) -> None:
        kunci = (tgl, jenis, rincian)
        jumlah[kunci] = jumlah.get(kunci, Decimal("0")) + nilai

    for t in transaksi:
        tgl = t.tanggal.date()
        tambah(tgl, "penjualan_bersih", "", Decimal(t.subtotal) - Decimal(t.total_diskon))
        tambah(tgl, "pajak_dipungut", "", Decimal(t.total_pajak))
        tambah(tgl, "hpp", "", hpp_per_transaksi.get(t.id, Decimal("0")))
    for tgl, metode, nilai in pembayaran:
        tambah(tgl, "penerimaan", metode, nilai)
    for tgl, kategori, nilai in biaya:
        tambah(tgl, "biaya", kategori, nilai)
    urut = sorted(jumlah, key=lambda k: (k[0], k[1], k[2]))
    return [(k[0].isoformat(), k[1], k[2], jumlah[k]) for k in urut]


def ke_csv(baris: list[tuple[str, str, str, Decimal]]) -> str:
    out = io.StringIO()
    w = csv.writer(out, lineterminator="\n")
    w.writerow(KOLOM)
    for tgl, jenis, rincian, nilai in baris:
        akun = akun_untuk_baris_ekspor(jenis, rincian)
        w.writerow((tgl, jenis, rincian, f"{nilai:.2f}", akun.kode if akun else "", akun.nama if akun else ""))
    return out.getvalue()


@router.get("", response_model=EksporOut)
async def ekspor(
    dari: date = Query(...),
    sampai: date = Query(...),
    toko_id: uuid.UUID = Depends(get_toko_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> EksporOut:
    if not await has_izin(db, role_id, "laporan.lihat"):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Role ini tidak punya izin laporan.lihat")
    if sampai < dari:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, "Tanggal sampai harus sesudah dari")
    if (sampai - dari).days > _MAKS_HARI:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, f"Rentang maksimal {_MAKS_HARI} hari")

    awal = datetime.combine(dari, time.min, tzinfo=UTC)
    akhir = datetime.combine(sampai + timedelta(days=1), time.min, tzinfo=UTC)
    transaksi = await _transaksi_selesai(db, toko_id, None, awal, akhir)
    items = await _item_untuk_transaksi(db, [t.id for t in transaksi])
    hpp: dict[uuid.UUID, Decimal] = {}
    for i in items:
        hpp[i.transaksi_id] = hpp.get(i.transaksi_id, Decimal("0")) + Decimal(i.hpp_satuan) * Decimal(i.qty)

    rows = (
        await db.execute(
            select(Pembayaran.jumlah, Pembayaran.dibayar_pada, Pembayaran.created_at, MetodeBayar.nama)
            .join(Transaksi, Transaksi.id == Pembayaran.transaksi_id)
            .join(MetodeBayar, MetodeBayar.id == Pembayaran.metode_bayar_id)
            .where(Transaksi.toko_id == toko_id, Transaksi.status == "selesai", Pembayaran.status == "berhasil")
        )
    ).all()
    pembayaran: list[tuple[date, str, Decimal]] = []
    for nilai, dibayar, dibuat, metode in rows:
        ts = dibayar or dibuat
        if awal <= ts.replace(tzinfo=ts.tzinfo or UTC) < akhir:
            pembayaran.append((ts.date(), metode, Decimal(nilai)))

    biaya = [
        (p.tanggal, p.kategori, Decimal(p.jumlah))
        for p in (
            await db.execute(
                select(Pengeluaran).where(
                    Pengeluaran.toko_id == toko_id,
                    Pengeluaran.deleted_at.is_(None),
                    Pengeluaran.tanggal >= dari,
                    Pengeluaran.tanggal <= sampai,
                )
            )
        ).scalars()
    ]
    baris = susun_baris(transaksi, hpp, pembayaran, biaya)
    return EksporOut(nama_berkas=f"akuntansi_{dari}_{sampai}.csv", jumlah_baris=len(baris), csv=ke_csv(baris))
