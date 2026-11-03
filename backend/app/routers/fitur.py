import uuid

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_db
from app.core.deps import get_toko_id
from app.models.fitur import Fitur
from app.schemas.fitur import FiturOut, FiturTokoOut
from app.services.fitur_service import kode_fitur_toko, paket_efektif

router = APIRouter(tags=["fitur"])


@router.get("/fitur", response_model=list[FiturOut])
async def daftar_fitur(db: AsyncSession = Depends(get_db)) -> list[Fitur]:
    rows = (await db.execute(select(Fitur).where(Fitur.deleted_at.is_(None)))).scalars().all()
    return list(rows)


@router.get("/fitur/toko", response_model=FiturTokoOut)
async def fitur_toko_saat_ini(
    toko_id: uuid.UUID = Depends(get_toko_id), db: AsyncSession = Depends(get_db)
) -> FiturTokoOut:
    paket = await paket_efektif(db, toko_id)
    kode = await kode_fitur_toko(db, toko_id)
    return FiturTokoOut(paket=paket.nama, kode_fitur=sorted(kode))
