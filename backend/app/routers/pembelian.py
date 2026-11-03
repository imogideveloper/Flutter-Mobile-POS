import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_db
from app.core.deps import get_pengguna_id, get_role_id, get_toko_id, require_outlet_access
from app.models.stok import Pembelian, Supplier
from app.schemas.pembelian import PembelianIn, PembelianOut, SupplierIn, SupplierOut
from app.services.pembelian_service import buat_pembelian, pembelian_ke_out, terima_pembelian

router = APIRouter(tags=["pembelian"])


@router.get("/supplier", response_model=list[SupplierOut])
async def daftar_supplier(
    toko_id: uuid.UUID = Depends(get_toko_id), db: AsyncSession = Depends(get_db)
) -> list[Supplier]:
    rows = (
        await db.execute(select(Supplier).where(Supplier.toko_id == toko_id, Supplier.deleted_at.is_(None)))
    ).scalars().all()
    return list(rows)


@router.post("/supplier", response_model=SupplierOut, status_code=status.HTTP_201_CREATED)
async def tambah_supplier(
    body: SupplierIn, toko_id: uuid.UUID = Depends(get_toko_id), db: AsyncSession = Depends(get_db)
) -> Supplier:
    supplier = Supplier(toko_id=toko_id, **body.model_dump())
    db.add(supplier)
    await db.commit()
    await db.refresh(supplier)
    return supplier


async def _ambil_pembelian_milik_toko(db: AsyncSession, pembelian_id: uuid.UUID, toko_id: uuid.UUID) -> Pembelian:
    pembelian = await db.get(Pembelian, pembelian_id)
    if pembelian is None or pembelian.toko_id != toko_id or pembelian.deleted_at is not None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Pembelian tidak ditemukan")
    return pembelian


@router.get("/pembelian", response_model=list[PembelianOut])
async def daftar_pembelian(
    toko_id: uuid.UUID = Depends(get_toko_id), db: AsyncSession = Depends(get_db)
) -> list[PembelianOut]:
    rows = (
        await db.execute(select(Pembelian).where(Pembelian.toko_id == toko_id, Pembelian.deleted_at.is_(None)))
    ).scalars().all()
    return [await pembelian_ke_out(db, p) for p in rows]


@router.post("/pembelian", response_model=PembelianOut, status_code=status.HTTP_201_CREATED)
async def tambah_pembelian(
    body: PembelianIn,
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> PembelianOut:
    return await buat_pembelian(db, toko_id=toko_id, pengguna_id=pengguna_id, role_id=role_id, body=body)


@router.get("/pembelian/{pembelian_id}", response_model=PembelianOut)
async def detail_pembelian(
    pembelian_id: uuid.UUID, toko_id: uuid.UUID = Depends(get_toko_id), db: AsyncSession = Depends(get_db)
) -> PembelianOut:
    pembelian = await _ambil_pembelian_milik_toko(db, pembelian_id, toko_id)
    return await pembelian_ke_out(db, pembelian)


@router.post("/pembelian/{pembelian_id}/terima", response_model=PembelianOut)
async def tandai_pembelian_diterima(
    pembelian_id: uuid.UUID,
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> PembelianOut:
    pembelian = await _ambil_pembelian_milik_toko(db, pembelian_id, toko_id)
    await require_outlet_access(db, pengguna_id=pengguna_id, role_id=role_id, outlet_id=pembelian.outlet_id)
    return await terima_pembelian(db, pembelian=pembelian, pengguna_id=pengguna_id)
