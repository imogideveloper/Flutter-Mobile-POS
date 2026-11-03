import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_db
from app.core.deps import get_pengguna_id, get_role_id, get_toko_id, require_outlet_access
from app.models.stok import TransferStok
from app.schemas.transfer_stok import TransferStokIn, TransferStokOut
from app.services.transfer_stok_service import buat_transfer, kirim_transfer, terima_transfer, transfer_ke_out

router = APIRouter(prefix="/transfer-stok", tags=["transfer-stok"])


async def _ambil_transfer_milik_toko(db: AsyncSession, transfer_id: uuid.UUID, toko_id: uuid.UUID) -> TransferStok:
    transfer = await db.get(TransferStok, transfer_id)
    if transfer is None or transfer.toko_id != toko_id or transfer.deleted_at is not None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Transfer stok tidak ditemukan")
    return transfer


@router.get("", response_model=list[TransferStokOut])
async def daftar_transfer(
    toko_id: uuid.UUID = Depends(get_toko_id), db: AsyncSession = Depends(get_db)
) -> list[TransferStokOut]:
    rows = (
        await db.execute(select(TransferStok).where(TransferStok.toko_id == toko_id, TransferStok.deleted_at.is_(None)))
    ).scalars().all()
    return [await transfer_ke_out(db, t) for t in rows]


@router.post("", response_model=TransferStokOut, status_code=status.HTTP_201_CREATED)
async def tambah_transfer(
    body: TransferStokIn,
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> TransferStokOut:
    return await buat_transfer(db, toko_id=toko_id, pengguna_id=pengguna_id, role_id=role_id, body=body)


@router.get("/{transfer_id}", response_model=TransferStokOut)
async def detail_transfer(
    transfer_id: uuid.UUID, toko_id: uuid.UUID = Depends(get_toko_id), db: AsyncSession = Depends(get_db)
) -> TransferStokOut:
    transfer = await _ambil_transfer_milik_toko(db, transfer_id, toko_id)
    return await transfer_ke_out(db, transfer)


@router.post("/{transfer_id}/kirim", response_model=TransferStokOut)
async def kirim(
    transfer_id: uuid.UUID,
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> TransferStokOut:
    transfer = await _ambil_transfer_milik_toko(db, transfer_id, toko_id)
    await require_outlet_access(db, pengguna_id=pengguna_id, role_id=role_id, outlet_id=transfer.dari_outlet_id)
    return await kirim_transfer(db, transfer=transfer, pengguna_id=pengguna_id)


@router.post("/{transfer_id}/terima", response_model=TransferStokOut)
async def terima(
    transfer_id: uuid.UUID,
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    db: AsyncSession = Depends(get_db),
) -> TransferStokOut:
    transfer = await _ambil_transfer_milik_toko(db, transfer_id, toko_id)
    return await terima_transfer(db, transfer=transfer, pengguna_id=pengguna_id)
