"""Modul 1 (toko) - endpoint level-toko yang bukan outlet/pengguna: unggah logo
(tahap 4 bagian B.2) dan gambar QRIS statis usaha (IMOGI no. 10)."""

import uuid

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_db
from app.core.deps import get_role_id, get_toko_id
from app.models.outlet import Toko
from app.schemas.toko import LogoOut, QrisOut
from app.services.fitur_service import require_fitur
from app.services.izin_service import has_izin
from app.services.storage_service import simpan_logo_toko, simpan_qris_toko

router = APIRouter(prefix="/toko", tags=["toko"])


@router.post("/logo", response_model=LogoOut, dependencies=[Depends(require_fitur("logo_struk"))])
async def unggah_logo_toko(
    file: UploadFile = File(...),
    toko_id: uuid.UUID = Depends(get_toko_id),
    db: AsyncSession = Depends(get_db),
) -> LogoOut:
    url = await simpan_logo_toko(toko_id, file)

    toko = await db.get(Toko, toko_id)
    toko.logo_url = url
    await db.commit()
    return LogoOut(logo_url=url)


async def _wajib_izin_pengaturan(db: AsyncSession, role_id: uuid.UUID) -> None:
    if not await has_izin(db, role_id, "pengaturan.kelola"):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Role ini tidak punya izin pengaturan.kelola")


@router.post("/qris", response_model=QrisOut, dependencies=[Depends(require_fitur("qris"))])
async def unggah_qris_toko(
    file: UploadFile = File(...),
    toko_id: uuid.UUID = Depends(get_toko_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> QrisOut:
    """Gambar QRIS statis milik usaha (PNG/JPG maks. 1 MB) yang ditampilkan kasir di layar bayar."""
    await _wajib_izin_pengaturan(db, role_id)
    url = await simpan_qris_toko(toko_id, file)

    toko = await db.get(Toko, toko_id)
    toko.qris_url = url
    await db.commit()
    return QrisOut(qris_url=url)


@router.delete("/qris", response_model=QrisOut)
async def hapus_qris_toko(
    toko_id: uuid.UUID = Depends(get_toko_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> QrisOut:
    """Hapus gambar QRIS (tidak digate paket: usaha yang turun paket tetap boleh menghapusnya)."""
    await _wajib_izin_pengaturan(db, role_id)
    toko = await db.get(Toko, toko_id)
    toko.qris_url = None
    await db.commit()
    return QrisOut(qris_url=None)
