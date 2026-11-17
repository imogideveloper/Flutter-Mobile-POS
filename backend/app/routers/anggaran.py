"""Anggaran & proyeksi (IMOGI no. 82).

Pemilik menetapkan anggaran biaya per kategori untuk satu bulan; server membandingkannya dengan realisasi
pengeluaran dan memproyeksikan akhir bulan secara linear (realisasi / hari berjalan x jumlah hari bulan)."""

import calendar
import uuid
from datetime import UTC, date, datetime, time, timedelta
from decimal import ROUND_HALF_UP, Decimal

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_db
from app.core.deps import get_role_id, get_toko_id
from app.models.anggaran import Anggaran
from app.models.pengeluaran import KATEGORI_PENGELUARAN, Pengeluaran
from app.models.transaksi import Transaksi
from app.services.fitur_service import require_fitur
from app.services.izin_service import has_izin
from app.services.tutup_buku_service import pastikan_periode_terbuka

router = APIRouter(prefix="/anggaran", tags=["anggaran"], dependencies=[Depends(require_fitur("budget"))])

_SEN = Decimal("0.01")


class AnggaranIn(BaseModel):
    bulan: str = Field(pattern=r"^\d{4}-(0[1-9]|1[0-2])$")  # YYYY-MM
    kategori: str
    jumlah: Decimal = Field(ge=0, le=Decimal("999999999999"))


class BarisAnggaranOut(BaseModel):
    kategori: str
    anggaran: Decimal
    realisasi: Decimal
    sisa: Decimal
    persen: Decimal | None  # realisasi / anggaran; null bila anggaran 0
    proyeksi: Decimal  # perkiraan realisasi akhir bulan
    status: str  # aman | waspada (>=80%) | lewat (>100%) | tanpa_anggaran


class RingkasanAnggaranOut(BaseModel):
    bulan: str
    hari_berjalan: int
    jumlah_hari: int
    baris: list[BarisAnggaranOut]
    total_anggaran: Decimal
    total_realisasi: Decimal
    total_proyeksi: Decimal
    penjualan_realisasi: Decimal
    penjualan_proyeksi: Decimal
    arus_kas_proyeksi: Decimal  # proyeksi penjualan - proyeksi biaya (kasar, bukan laporan arus kas akuntansi)


def _awal_bulan(bulan: str) -> date:
    tahun, bln = bulan.split("-")
    return date(int(tahun), int(bln), 1)


async def _wajib_izin(db: AsyncSession, role_id: uuid.UUID) -> None:
    if not await has_izin(db, role_id, "laporan.lihat"):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Role ini tidak punya izin laporan.lihat")


@router.put("", status_code=status.HTTP_204_NO_CONTENT)
async def tetapkan_anggaran(
    body: AnggaranIn,
    toko_id: uuid.UUID = Depends(get_toko_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> None:
    await _wajib_izin(db, role_id)
    if body.kategori not in KATEGORI_PENGELUARAN:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, "Kategori tidak dikenal")
    awal = _awal_bulan(body.bulan)
    await pastikan_periode_terbuka(db, toko_id, awal)
    ada = (
        await db.execute(
            select(Anggaran).where(Anggaran.toko_id == toko_id, Anggaran.bulan == awal, Anggaran.kategori == body.kategori)
        )
    ).scalar_one_or_none()
    if ada is None:
        db.add(Anggaran(toko_id=toko_id, bulan=awal, kategori=body.kategori, jumlah=body.jumlah))
    else:
        ada.jumlah = body.jumlah
        ada.deleted_at = None
    await db.commit()


@router.get("", response_model=RingkasanAnggaranOut)
async def ringkasan_anggaran(
    bulan: str = Query(pattern=r"^\d{4}-(0[1-9]|1[0-2])$"),
    per: date | None = Query(default=None),
    toko_id: uuid.UUID = Depends(get_toko_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> RingkasanAnggaranOut:
    await _wajib_izin(db, role_id)
    awal = _awal_bulan(bulan)
    jumlah_hari = calendar.monthrange(awal.year, awal.month)[1]
    akhir = date(awal.year, awal.month, jumlah_hari)
    hari_ini = per or datetime.now(UTC).date()
    if hari_ini < awal:
        berjalan = 0
    elif hari_ini > akhir:
        berjalan = jumlah_hari
    else:
        berjalan = hari_ini.day

    def proyeksikan(nilai: Decimal) -> Decimal:
        if berjalan == 0 or berjalan >= jumlah_hari:
            return nilai
        return (nilai / berjalan * jumlah_hari).quantize(_SEN, ROUND_HALF_UP)

    anggaran = {
        a.kategori: Decimal(a.jumlah)
        for a in (
            await db.execute(
                select(Anggaran).where(Anggaran.toko_id == toko_id, Anggaran.bulan == awal, Anggaran.deleted_at.is_(None))
            )
        ).scalars()
    }
    realisasi: dict[str, Decimal] = {}
    for p in (
        await db.execute(
            select(Pengeluaran).where(
                Pengeluaran.toko_id == toko_id,
                Pengeluaran.deleted_at.is_(None),
                Pengeluaran.tanggal >= awal,
                Pengeluaran.tanggal <= akhir,
            )
        )
    ).scalars():
        realisasi[p.kategori] = realisasi.get(p.kategori, Decimal("0")) + Decimal(p.jumlah)

    baris: list[BarisAnggaranOut] = []
    for kategori in KATEGORI_PENGELUARAN:
        a = anggaran.get(kategori)
        r = realisasi.get(kategori, Decimal("0"))
        if a is None and r == 0:
            continue
        if a is None or a == 0:
            persen, st = None, "tanpa_anggaran"
        else:
            persen = (r / a).quantize(Decimal("0.0001"), ROUND_HALF_UP)
            st = "lewat" if r > a else ("waspada" if persen >= Decimal("0.8") else "aman")
        baris.append(
            BarisAnggaranOut(
                kategori=kategori,
                anggaran=a or Decimal("0"),
                realisasi=r,
                sisa=(a or Decimal("0")) - r,
                persen=persen,
                proyeksi=proyeksikan(r),
                status=st,
            )
        )

    awal_dt = datetime.combine(awal, time.min, tzinfo=UTC)
    akhir_dt = datetime.combine(akhir + timedelta(days=1), time.min, tzinfo=UTC)
    penjualan = sum(
        (
            Decimal(t)
            for (t,) in (
                await db.execute(
                    select(Transaksi.total).where(
                        Transaksi.toko_id == toko_id,
                        Transaksi.status == "selesai",
                        Transaksi.tanggal >= awal_dt,
                        Transaksi.tanggal < akhir_dt,
                    )
                )
            ).all()
        ),
        Decimal("0"),
    )
    total_realisasi = sum((b.realisasi for b in baris), Decimal("0"))
    total_proyeksi = sum((b.proyeksi for b in baris), Decimal("0"))
    penjualan_proyeksi = proyeksikan(penjualan)
    return RingkasanAnggaranOut(
        bulan=bulan,
        hari_berjalan=berjalan,
        jumlah_hari=jumlah_hari,
        baris=baris,
        total_anggaran=sum((b.anggaran for b in baris), Decimal("0")),
        total_realisasi=total_realisasi,
        total_proyeksi=total_proyeksi,
        penjualan_realisasi=penjualan,
        penjualan_proyeksi=penjualan_proyeksi,
        arus_kas_proyeksi=penjualan_proyeksi - total_proyeksi,
    )


class SalinIn(BaseModel):
    dari: str = Field(pattern=r"^\d{4}-(0[1-9]|1[0-2])$")
    ke: str = Field(pattern=r"^\d{4}-(0[1-9]|1[0-2])$")


class SalinOut(BaseModel):
    disalin: int


@router.post("/salin", response_model=SalinOut, status_code=status.HTTP_201_CREATED)
async def salin_anggaran(
    body: SalinIn,
    toko_id: uuid.UUID = Depends(get_toko_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> SalinOut:
    """Menyalin anggaran satu bulan ke bulan lain. Kategori yang sudah dianggarkan di bulan tujuan tidak ditimpa."""
    await _wajib_izin(db, role_id)
    if body.dari == body.ke:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, "Bulan asal dan tujuan harus berbeda")
    asal, tujuan = _awal_bulan(body.dari), _awal_bulan(body.ke)
    await pastikan_periode_terbuka(db, toko_id, tujuan)
    sumber = (
        await db.execute(
            select(Anggaran).where(Anggaran.toko_id == toko_id, Anggaran.bulan == asal, Anggaran.deleted_at.is_(None))
        )
    ).scalars().all()
    if not sumber:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Bulan asal belum punya anggaran")
    ada = {
        a.kategori: a
        for a in (
            await db.execute(select(Anggaran).where(Anggaran.toko_id == toko_id, Anggaran.bulan == tujuan))
        ).scalars()
    }
    disalin = 0
    for s in sumber:
        sudah = ada.get(s.kategori)
        if sudah is not None and sudah.deleted_at is None:
            continue
        if sudah is not None:
            sudah.jumlah = s.jumlah
            sudah.deleted_at = None
        else:
            db.add(Anggaran(toko_id=toko_id, bulan=tujuan, kategori=s.kategori, jumlah=s.jumlah))
        disalin += 1
    await db.commit()
    return SalinOut(disalin=disalin)
