"""Settlement & rekonsiliasi QRIS/e-wallet (IMOGI no. 74).

Pemilik mencatat dana yang masuk rekening dari penyedia pembayaran (per tanggal penjualan dan metode), lalu
membandingkannya dengan penjualan non-tunai yang tercatat di POS. Selisih = tercatat - diterima - biaya."""

import uuid
from datetime import UTC, date, datetime, time, timedelta, timezone
from decimal import Decimal

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, Field
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_db
from app.core.deps import get_role_id, get_toko_id
from app.models.settlement import Settlement
from app.models.transaksi import MetodeBayar, Pembayaran, Transaksi
from app.services.fitur_service import require_fitur
from app.services.izin_service import has_izin
from app.services.tutup_buku_service import pastikan_periode_terbuka

router = APIRouter(prefix="/settlement", tags=["settlement"], dependencies=[Depends(require_fitur("settlement"))])

# Metode non-tunai yang dananya dicairkan penyedia ke rekening toko.
_TIPE_NONTUNAI = ("qris", "ewallet", "kartu", "transfer")
_MAKS_HARI = 93


class SettlementIn(BaseModel):
    metode_bayar_id: uuid.UUID
    tanggal: date
    jumlah_diterima: Decimal = Field(ge=0, le=Decimal("999999999999"))
    biaya: Decimal = Field(default=Decimal("0"), ge=0, le=Decimal("999999999999"))
    referensi: str | None = Field(default=None, max_length=100)
    catatan: str | None = Field(default=None, max_length=500)


class SettlementOut(BaseModel):
    id: uuid.UUID
    metode_bayar_id: uuid.UUID
    metode_nama: str
    tanggal: date
    jumlah_diterima: Decimal
    biaya: Decimal
    referensi: str | None
    catatan: str | None


class BarisRekonsiliasi(BaseModel):
    tanggal: date
    metode_bayar_id: uuid.UUID
    metode_nama: str
    tercatat: Decimal
    diterima: Decimal
    biaya: Decimal
    selisih: Decimal
    status: str  # cocok | selisih | belum_dicatat


class RekonsiliasiOut(BaseModel):
    baris: list[BarisRekonsiliasi]
    total_tercatat: Decimal
    total_diterima: Decimal
    total_biaya: Decimal
    total_selisih: Decimal


async def _wajib_izin(db: AsyncSession, role_id: uuid.UUID) -> None:
    if not await has_izin(db, role_id, "laporan.lihat"):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Role ini tidak punya izin laporan.lihat")


def _periksa_rentang(dari: date, sampai: date) -> None:
    if sampai < dari:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, "Tanggal sampai harus sesudah dari")
    if (sampai - dari).days > _MAKS_HARI:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, f"Rentang maksimal {_MAKS_HARI} hari")


async def _metode_nontunai_milik_toko(db: AsyncSession, metode_id: uuid.UUID, toko_id: uuid.UUID) -> MetodeBayar:
    metode = await db.get(MetodeBayar, metode_id)
    if metode is None or metode.toko_id != toko_id or metode.deleted_at is not None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Metode pembayaran tidak ditemukan")
    if metode.tipe not in _TIPE_NONTUNAI:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, "Settlement hanya untuk metode non-tunai")
    return metode


def _keluaran(s: Settlement, nama: str) -> SettlementOut:
    return SettlementOut(
        id=s.id,
        metode_bayar_id=s.metode_bayar_id,
        metode_nama=nama,
        tanggal=s.tanggal,
        jumlah_diterima=Decimal(s.jumlah_diterima),
        biaya=Decimal(s.biaya),
        referensi=s.referensi,
        catatan=s.catatan,
    )


@router.post("", response_model=SettlementOut, status_code=status.HTTP_201_CREATED)
async def catat_settlement(
    body: SettlementIn,
    toko_id: uuid.UUID = Depends(get_toko_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> SettlementOut:
    await _wajib_izin(db, role_id)
    await pastikan_periode_terbuka(db, toko_id, body.tanggal)
    metode = await _metode_nontunai_milik_toko(db, body.metode_bayar_id, toko_id)
    s = Settlement(
        toko_id=toko_id,
        metode_bayar_id=metode.id,
        tanggal=body.tanggal,
        jumlah_diterima=body.jumlah_diterima,
        biaya=body.biaya,
        referensi=(body.referensi or "").strip() or None,
        catatan=(body.catatan or "").strip() or None,
    )
    db.add(s)
    await db.commit()
    await db.refresh(s)
    return _keluaran(s, metode.nama)


@router.get("", response_model=list[SettlementOut])
async def daftar_settlement(
    dari: date = Query(...),
    sampai: date = Query(...),
    toko_id: uuid.UUID = Depends(get_toko_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> list[SettlementOut]:
    await _wajib_izin(db, role_id)
    _periksa_rentang(dari, sampai)
    rows = (
        await db.execute(
            select(Settlement, MetodeBayar.nama)
            .join(MetodeBayar, MetodeBayar.id == Settlement.metode_bayar_id)
            .where(
                Settlement.toko_id == toko_id,
                Settlement.deleted_at.is_(None),
                Settlement.tanggal >= dari,
                Settlement.tanggal <= sampai,
            )
            .order_by(Settlement.tanggal.desc(), Settlement.created_at.desc())
        )
    ).all()
    return [_keluaran(s, nama) for s, nama in rows]


@router.delete("/{settlement_id}", status_code=status.HTTP_204_NO_CONTENT)
async def hapus_settlement(
    settlement_id: uuid.UUID,
    toko_id: uuid.UUID = Depends(get_toko_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> None:
    await _wajib_izin(db, role_id)
    s = await db.get(Settlement, settlement_id)
    if s is None or s.toko_id != toko_id or s.deleted_at is not None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Settlement tidak ditemukan")
    await pastikan_periode_terbuka(db, toko_id, s.tanggal)
    s.deleted_at = datetime.now(UTC)
    await db.commit()


@router.get("/rekonsiliasi", response_model=RekonsiliasiOut)
async def rekonsiliasi(
    dari: date = Query(...),
    sampai: date = Query(...),
    # Offset zona waktu HP (menit). Tanpa ini pembayaran 00.00-07.00 WIB tercatat di tanggal UTC sehari sebelumnya.
    tz_menit: int = Query(0, ge=-840, le=840),
    toko_id: uuid.UUID = Depends(get_toko_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> RekonsiliasiOut:
    await _wajib_izin(db, role_id)
    _periksa_rentang(dari, sampai)
    zona = timezone(timedelta(minutes=tz_menit))
    awal = datetime.combine(dari, time.min, tzinfo=zona)
    akhir = datetime.combine(sampai + timedelta(days=1), time.min, tzinfo=zona)
    waktu = func.coalesce(Pembayaran.dibayar_pada, Pembayaran.created_at)

    pembayaran = (
        await db.execute(
            select(Pembayaran.jumlah, waktu, MetodeBayar.id, MetodeBayar.nama)
            .join(Transaksi, Transaksi.id == Pembayaran.transaksi_id)
            .join(MetodeBayar, MetodeBayar.id == Pembayaran.metode_bayar_id)
            .where(
                Transaksi.toko_id == toko_id,
                Transaksi.status == "selesai",
                Pembayaran.status == "berhasil",
                MetodeBayar.tipe.in_(_TIPE_NONTUNAI),
                waktu >= awal,
                waktu < akhir,
            )
        )
    ).all()

    nama: dict[uuid.UUID, str] = {}
    tercatat: dict[tuple[date, uuid.UUID], Decimal] = {}
    for jumlah, ts, metode_id, metode_nama in pembayaran:
        nama[metode_id] = metode_nama
        kunci = ((ts if ts.tzinfo else ts.replace(tzinfo=UTC)).astimezone(zona).date(), metode_id)
        tercatat[kunci] = tercatat.get(kunci, Decimal("0")) + Decimal(jumlah)

    diterima: dict[tuple[date, uuid.UUID], tuple[Decimal, Decimal]] = {}
    catatan = (
        await db.execute(
            select(Settlement, MetodeBayar.nama)
            .join(MetodeBayar, MetodeBayar.id == Settlement.metode_bayar_id)
            .where(
                Settlement.toko_id == toko_id,
                Settlement.deleted_at.is_(None),
                Settlement.tanggal >= dari,
                Settlement.tanggal <= sampai,
            )
        )
    ).all()
    for s, metode_nama in catatan:
        nama[s.metode_bayar_id] = metode_nama
        kunci = (s.tanggal, s.metode_bayar_id)
        sebelumnya = diterima.get(kunci, (Decimal("0"), Decimal("0")))
        diterima[kunci] = (sebelumnya[0] + Decimal(s.jumlah_diterima), sebelumnya[1] + Decimal(s.biaya))

    baris: list[BarisRekonsiliasi] = []
    for kunci in sorted(set(tercatat) | set(diterima), key=lambda k: (k[0], nama[k[1]])):
        tgl, metode_id = kunci
        tc = tercatat.get(kunci, Decimal("0"))
        dt, bya = diterima.get(kunci, (Decimal("0"), Decimal("0")))
        selisih = tc - dt - bya
        if kunci not in diterima:
            st = "belum_dicatat"
        else:
            st = "cocok" if selisih == 0 else "selisih"
        baris.append(
            BarisRekonsiliasi(
                tanggal=tgl,
                metode_bayar_id=metode_id,
                metode_nama=nama[metode_id],
                tercatat=tc,
                diterima=dt,
                biaya=bya,
                selisih=selisih,
                status=st,
            )
        )
    nol = Decimal("0")
    return RekonsiliasiOut(
        baris=baris,
        total_tercatat=sum((b.tercatat for b in baris), nol),
        total_diterima=sum((b.diterima for b in baris), nol),
        total_biaya=sum((b.biaya for b in baris), nol),
        total_selisih=sum((b.selisih for b in baris), nol),
    )
