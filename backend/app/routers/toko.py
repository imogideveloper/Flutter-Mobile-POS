"""Modul 1 (toko) - endpoint level-toko yang bukan outlet/pengguna. Baru
satu: upload logo (tahap 4 bagian B.2)."""

import uuid

from fastapi import APIRouter, Depends, File, UploadFile
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_db
from app.core.deps import get_toko_id
from app.models.outlet import Toko
from app.schemas.toko import LogoOut
from app.services.fitur_service import require_fitur
from app.services.storage_service import simpan_logo_toko

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
