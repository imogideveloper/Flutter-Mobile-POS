import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_db
from app.core.deps import get_pengguna_id, get_role_id, get_toko_id, require_outlet_access
from app.models.outlet import Outlet
from app.models.stok import StokOpname
from app.schemas.stok_opname import StokOpnameIn, StokOpnameOut
from app.services.stok_opname_service import buat_opname, opname_ke_out, selesaikan_opname

router = APIRouter(prefix="/stok-opname", tags=["stok-opname"])


async def _pastikan_outlet_milik_toko(db: AsyncSession, outlet_id: uuid.UUID, toko_id: uuid.UUID) -> None:
    outlet = await db.get(Outlet, outlet_id)
    if outlet is None or outlet.toko_id != toko_id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Outlet tidak ditemukan")


async def _ambil_opname_milik_toko(db: AsyncSession, opname_id: uuid.UUID, toko_id: uuid.UUID) -> StokOpname:
    opname = await db.get(StokOpname, opname_id)
    if opname is None or opname.deleted_at is not None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Stok opname tidak ditemukan")
    await _pastikan_outlet_milik_toko(db, opname.outlet_id, toko_id)
    return opname


@router.get("", response_model=list[StokOpnameOut])
async def daftar_opname(
    outlet_id: uuid.UUID,
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> list[StokOpnameOut]:
    await _pastikan_outlet_milik_toko(db, outlet_id, toko_id)
    await require_outlet_access(db, pengguna_id=pengguna_id, role_id=role_id, outlet_id=outlet_id)
    rows = (
        await db.execute(
            select(StokOpname).where(StokOpname.outlet_id == outlet_id, StokOpname.deleted_at.is_(None))
        )
    ).scalars().all()
    return [await opname_ke_out(db, o) for o in rows]


@router.post("", response_model=StokOpnameOut, status_code=status.HTTP_201_CREATED)
async def tambah_opname(
    body: StokOpnameIn,
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> StokOpnameOut:
    await _pastikan_outlet_milik_toko(db, body.outlet_id, toko_id)
    await require_outlet_access(db, pengguna_id=pengguna_id, role_id=role_id, outlet_id=body.outlet_id)
    return await buat_opname(db, toko_id=toko_id, pengguna_id=pengguna_id, body=body)


@router.get("/{opname_id}", response_model=StokOpnameOut)
async def detail_opname(
    opname_id: uuid.UUID, toko_id: uuid.UUID = Depends(get_toko_id), db: AsyncSession = Depends(get_db)
) -> StokOpnameOut:
    opname = await _ambil_opname_milik_toko(db, opname_id, toko_id)
    return await opname_ke_out(db, opname)


@router.post("/{opname_id}/selesai", response_model=StokOpnameOut)
async def tandai_opname_selesai(
    opname_id: uuid.UUID,
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> StokOpnameOut:
    opname = await _ambil_opname_milik_toko(db, opname_id, toko_id)
    await require_outlet_access(db, pengguna_id=pengguna_id, role_id=role_id, outlet_id=opname.outlet_id)
    return await selesaikan_opname(db, opname=opname, pengguna_id=pengguna_id)
