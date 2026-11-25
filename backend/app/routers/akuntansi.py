"""Bagan akun standar (IMOGI no. 80, tahap 1): daftar akun tetap dan pemetaan kategori pengeluaran ke akun.
Hanya baca; lihat services/coa_standar.py."""

import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_db
from app.core.deps import get_role_id
from app.services.coa_standar import AKUN_KATEGORI_PENGELUARAN, AKUN_STANDAR
from app.services.fitur_service import require_fitur
from app.services.izin_service import has_izin

router = APIRouter(prefix="/akuntansi", tags=["akuntansi"], dependencies=[Depends(require_fitur("journal"))])


class AkunOut(BaseModel):
    kode: str
    nama: str
    kelompok: str
    saldo_normal: str


class PemetaanOut(BaseModel):
    kategori: str
    kode_akun: str


class CoaOut(BaseModel):
    akun: list[AkunOut]
    pemetaan_pengeluaran: list[PemetaanOut]


@router.get("/coa", response_model=CoaOut)
async def daftar_akun(
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> CoaOut:
    if not await has_izin(db, role_id, "laporan.lihat"):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Role ini tidak punya izin laporan.lihat")
    return CoaOut(
        akun=[AkunOut(kode=a.kode, nama=a.nama, kelompok=a.kelompok, saldo_normal=a.saldo_normal) for a in AKUN_STANDAR],
        pemetaan_pengeluaran=[PemetaanOut(kategori=k, kode_akun=v) for k, v in AKUN_KATEGORI_PENGELUARAN.items()],
    )
