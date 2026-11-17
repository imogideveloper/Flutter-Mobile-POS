"""Aset tetap & penyusutan (IMOGI no. 83).

Penyusutan garis lurus per bulan: (harga perolehan - nilai residu) / umur (bulan). Penyusutan dimulai pada bulan
perolehan (bulan penuh) dan berhenti saat umur habis; nilai buku tidak turun di bawah nilai residu."""

import uuid
from datetime import UTC, date, datetime
from decimal import ROUND_HALF_UP, Decimal

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_db
from app.core.deps import get_role_id, get_toko_id
from app.models.aset_tetap import AsetTetap
from app.services.fitur_service import require_fitur
from app.services.izin_service import has_izin
from app.services.tutup_buku_service import pastikan_periode_terbuka

router = APIRouter(prefix="/aset-tetap", tags=["aset-tetap"], dependencies=[Depends(require_fitur("fixed_assets"))])

_SEN = Decimal("0.01")


class AsetIn(BaseModel):
    nama: str = Field(min_length=1, max_length=150)
    tanggal_perolehan: date
    harga_perolehan: Decimal = Field(gt=0, le=Decimal("999999999999"))
    nilai_residu: Decimal = Field(default=Decimal("0"), ge=0)
    umur_bulan: int = Field(gt=0, le=600)
    catatan: str | None = Field(default=None, max_length=500)


class AsetUpdateIn(BaseModel):
    nama: str | None = Field(default=None, min_length=1, max_length=150)
    tanggal_perolehan: date | None = None
    harga_perolehan: Decimal | None = Field(default=None, gt=0, le=Decimal("999999999999"))
    nilai_residu: Decimal | None = Field(default=None, ge=0)
    umur_bulan: int | None = Field(default=None, gt=0, le=600)
    catatan: str | None = Field(default=None, max_length=500)


class AsetOut(BaseModel):
    id: uuid.UUID
    nama: str
    tanggal_perolehan: date
    harga_perolehan: Decimal
    nilai_residu: Decimal
    umur_bulan: int
    catatan: str | None
    penyusutan_per_bulan: Decimal
    bulan_berjalan: int
    akumulasi_penyusutan: Decimal
    nilai_buku: Decimal
    penyusutan_bulan_ini: Decimal


class RingkasanAsetOut(BaseModel):
    per: date
    aset: list[AsetOut]
    total_harga_perolehan: Decimal
    total_akumulasi: Decimal
    total_nilai_buku: Decimal
    total_penyusutan_bulan_ini: Decimal


def hitung_penyusutan(a: AsetTetap, per: date) -> AsetOut:
    """Penyusutan aset [a] per tanggal [per] (tanpa menyentuh DB)."""
    harga = Decimal(a.harga_perolehan)
    residu = Decimal(a.nilai_residu)
    umur = int(a.umur_bulan)
    per_bulan = ((harga - residu) / umur).quantize(_SEN, ROUND_HALF_UP)
    terlewat = (per.year - a.tanggal_perolehan.year) * 12 + per.month - a.tanggal_perolehan.month + 1
    bulan = max(0, min(terlewat, umur))
    # Bulan terakhir menyerap sisa pembulatan supaya nilai buku akhir tepat sama dengan nilai residu.
    akumulasi = (harga - residu) if bulan >= umur else (per_bulan * bulan)
    ini = Decimal("0")
    if 0 < terlewat <= umur:
        sebelum = (harga - residu) if terlewat - 1 >= umur else per_bulan * (terlewat - 1)
        ini = akumulasi - sebelum
    return AsetOut(
        id=a.id,
        nama=a.nama,
        tanggal_perolehan=a.tanggal_perolehan,
        harga_perolehan=harga,
        nilai_residu=residu,
        umur_bulan=umur,
        catatan=a.catatan,
        penyusutan_per_bulan=per_bulan,
        bulan_berjalan=bulan,
        akumulasi_penyusutan=akumulasi,
        nilai_buku=harga - akumulasi,
        penyusutan_bulan_ini=ini,
    )


async def _wajib_izin(db: AsyncSession, role_id: uuid.UUID) -> None:
    if not await has_izin(db, role_id, "laporan.lihat"):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Role ini tidak punya izin laporan.lihat")


async def _aset_milik_toko(db: AsyncSession, aset_id: uuid.UUID, toko_id: uuid.UUID) -> AsetTetap:
    aset = await db.get(AsetTetap, aset_id)
    if aset is None or aset.toko_id != toko_id or aset.deleted_at is not None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Aset tidak ditemukan")
    return aset


@router.post("", response_model=AsetOut, status_code=status.HTTP_201_CREATED)
async def tambah_aset(
    body: AsetIn,
    toko_id: uuid.UUID = Depends(get_toko_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> AsetOut:
    await _wajib_izin(db, role_id)
    await pastikan_periode_terbuka(db, toko_id, body.tanggal_perolehan)
    if body.nilai_residu >= body.harga_perolehan:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, "Nilai residu harus lebih kecil dari harga perolehan")
    aset = AsetTetap(
        toko_id=toko_id,
        nama=body.nama.strip(),
        tanggal_perolehan=body.tanggal_perolehan,
        harga_perolehan=body.harga_perolehan,
        nilai_residu=body.nilai_residu,
        umur_bulan=body.umur_bulan,
        catatan=(body.catatan or "").strip() or None,
    )
    db.add(aset)
    await db.commit()
    await db.refresh(aset)
    return hitung_penyusutan(aset, datetime.now(UTC).date())


@router.get("", response_model=RingkasanAsetOut)
async def daftar_aset(
    per: date | None = Query(default=None),
    toko_id: uuid.UUID = Depends(get_toko_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> RingkasanAsetOut:
    await _wajib_izin(db, role_id)
    tanggal = per or datetime.now(UTC).date()
    rows = (
        await db.execute(
            select(AsetTetap)
            .where(AsetTetap.toko_id == toko_id, AsetTetap.deleted_at.is_(None))
            .order_by(AsetTetap.tanggal_perolehan, AsetTetap.created_at)
        )
    ).scalars().all()
    # Aset yang belum diperoleh pada [per] tidak ikut dihitung.
    aset = [hitung_penyusutan(a, tanggal) for a in rows if a.tanggal_perolehan <= tanggal]
    nol = Decimal("0")
    return RingkasanAsetOut(
        per=tanggal,
        aset=aset,
        total_harga_perolehan=sum((a.harga_perolehan for a in aset), nol),
        total_akumulasi=sum((a.akumulasi_penyusutan for a in aset), nol),
        total_nilai_buku=sum((a.nilai_buku for a in aset), nol),
        total_penyusutan_bulan_ini=sum((a.penyusutan_bulan_ini for a in aset), nol),
    )


@router.patch("/{aset_id}", response_model=AsetOut)
async def ubah_aset(
    aset_id: uuid.UUID,
    body: AsetUpdateIn,
    toko_id: uuid.UUID = Depends(get_toko_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> AsetOut:
    await _wajib_izin(db, role_id)
    aset = await _aset_milik_toko(db, aset_id, toko_id)
    await pastikan_periode_terbuka(db, toko_id, aset.tanggal_perolehan)
    if body.tanggal_perolehan is not None:
        await pastikan_periode_terbuka(db, toko_id, body.tanggal_perolehan)
        aset.tanggal_perolehan = body.tanggal_perolehan
    if body.harga_perolehan is not None:
        aset.harga_perolehan = body.harga_perolehan
    if body.nilai_residu is not None:
        aset.nilai_residu = body.nilai_residu
    if body.umur_bulan is not None:
        aset.umur_bulan = body.umur_bulan
    if Decimal(aset.nilai_residu) >= Decimal(aset.harga_perolehan):
        await db.rollback()
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, "Nilai residu harus lebih kecil dari harga perolehan")
    if body.nama is not None:
        aset.nama = body.nama.strip()
    if body.catatan is not None:
        aset.catatan = body.catatan.strip() or None
    await db.commit()
    await db.refresh(aset)
    return hitung_penyusutan(aset, datetime.now(UTC).date())


@router.delete("/{aset_id}", status_code=status.HTTP_204_NO_CONTENT)
async def hapus_aset(
    aset_id: uuid.UUID,
    toko_id: uuid.UUID = Depends(get_toko_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> None:
    await _wajib_izin(db, role_id)
    aset = await _aset_milik_toko(db, aset_id, toko_id)
    await pastikan_periode_terbuka(db, toko_id, aset.tanggal_perolehan)
    aset.deleted_at = datetime.now(UTC)
    await db.commit()
