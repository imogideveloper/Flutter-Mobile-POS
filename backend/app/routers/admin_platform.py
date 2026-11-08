"""Pengaturan tingkat platform untuk ADMIN Imogi (bukan owner toko) -
dilindungi API key statis seperti admin_langganan.py. Ini pintu belakang
sementara; dashboard admin Imogi nanti memakai endpoint yang sama."""

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.admin_auth import verifikasi_admin_api_key
from app.core.db import get_db
from app.services.platform_service import (
    DEFAULT_TRIAL_NOTIFIKASI_HARI,
    KUNCI_TRIAL_NOTIFIKASI_HARI,
    KUNCI_USIA_AKUN_BULAN,
    ambil_int,
    simpan_int,
)

router = APIRouter(
    prefix="/admin/pengaturan-platform", tags=["admin"], dependencies=[Depends(verifikasi_admin_api_key)]
)


class PengaturanPlatformOut(BaseModel):
    usia_akun_bulan: int
    trial_notifikasi_hari: int


class PengaturanPlatformIn(BaseModel):
    # Lama masa trial dari tanggal toko mendaftar, dalam bulan. 0 = trial dimatikan.
    usia_akun_bulan: int | None = Field(default=None, ge=0, le=120)
    # Berapa hari sebelum trial berakhir notifikasi dikirim.
    trial_notifikasi_hari: int | None = Field(default=None, ge=1, le=365)


async def _baca(db: AsyncSession) -> PengaturanPlatformOut:
    return PengaturanPlatformOut(
        usia_akun_bulan=await ambil_int(db, KUNCI_USIA_AKUN_BULAN, 0),
        trial_notifikasi_hari=await ambil_int(db, KUNCI_TRIAL_NOTIFIKASI_HARI, DEFAULT_TRIAL_NOTIFIKASI_HARI),
    )


@router.get("", response_model=PengaturanPlatformOut)
async def ambil(db: AsyncSession = Depends(get_db)) -> PengaturanPlatformOut:
    return await _baca(db)


@router.put("", response_model=PengaturanPlatformOut)
async def ubah(body: PengaturanPlatformIn, db: AsyncSession = Depends(get_db)) -> PengaturanPlatformOut:
    if body.usia_akun_bulan is None and body.trial_notifikasi_hari is None:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, "Isi minimal satu pengaturan")
    if body.usia_akun_bulan is not None:
        await simpan_int(db, KUNCI_USIA_AKUN_BULAN, body.usia_akun_bulan)
    if body.trial_notifikasi_hari is not None:
        await simpan_int(db, KUNCI_TRIAL_NOTIFIKASI_HARI, body.trial_notifikasi_hari)
    return await _baca(db)
