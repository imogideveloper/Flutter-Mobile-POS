"""Batch stok dan pengingat kedaluwarsa produk (IMOGI no. 50).

Batch adalah catatan "sekian unit produk X kedaluwarsa pada tanggal Y". Saat ini
batch HANYA pengingat: penjualan belum memotong `qty_sisa` (FIFO belum dibuat),
jadi `qty_sisa` diisi sama dengan `qty_awal` dan diperbarui manual."""

import uuid
from datetime import date

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_db
from app.core.deps import get_pengguna_id, get_role_id, get_toko_id, require_outlet_access
from app.models.outlet import Outlet
from app.models.produk import Produk
from app.models.stok import BatchStok
from app.services.fitur_service import require_fitur
from app.services.izin_service import has_izin

router = APIRouter(prefix="/stok/batch", tags=["stok-batch"])


class BatchStokIn(BaseModel):
    outlet_id: uuid.UUID
    produk_id: uuid.UUID
    nomor_batch: str | None = Field(default=None, max_length=50)
    tanggal_kedaluwarsa: date
    qty: float = Field(gt=0)
    ingatkan_hari: int = Field(default=30, ge=0, le=365)


class BatchStokOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    outlet_id: uuid.UUID
    produk_id: uuid.UUID
    nomor_batch: str | None
    tanggal_kedaluwarsa: date
    qty_awal: float
    qty_sisa: float
    ingatkan_hari: int


async def _outlet_milik_toko(db: AsyncSession, outlet_id: uuid.UUID, toko_id: uuid.UUID) -> None:
    outlet = await db.get(Outlet, outlet_id)
    if outlet is None or outlet.toko_id != toko_id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Outlet tidak ditemukan")


async def _wajib_izin_stok(db: AsyncSession, role_id: uuid.UUID) -> None:
    if not await has_izin(db, role_id, "stok.kelola"):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Role ini tidak punya izin stok.kelola")


@router.get("", response_model=list[BatchStokOut])
async def daftar_batch(
    outlet_id: uuid.UUID,
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> list[BatchStokOut]:
    await _outlet_milik_toko(db, outlet_id, toko_id)
    await require_outlet_access(db, pengguna_id=pengguna_id, role_id=role_id, outlet_id=outlet_id)
    rows = (
        await db.execute(
            select(BatchStok)
            .where(BatchStok.outlet_id == outlet_id, BatchStok.deleted_at.is_(None))
            .order_by(BatchStok.tanggal_kedaluwarsa.asc())
        )
    ).scalars().all()
    return [BatchStokOut.model_validate(r) for r in rows]


@router.post(
    "",
    response_model=BatchStokOut,
    status_code=status.HTTP_201_CREATED,
    dependencies=[Depends(require_fitur("pengingat_kedaluwarsa"))],
)
async def tambah_batch(
    body: BatchStokIn,
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> BatchStokOut:
    await _wajib_izin_stok(db, role_id)
    await _outlet_milik_toko(db, body.outlet_id, toko_id)
    await require_outlet_access(db, pengguna_id=pengguna_id, role_id=role_id, outlet_id=body.outlet_id)
    produk = await db.get(Produk, body.produk_id)
    if produk is None or produk.toko_id != toko_id or produk.deleted_at is not None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Produk tidak ditemukan")

    batch = BatchStok(
        outlet_id=body.outlet_id,
        produk_id=body.produk_id,
        nomor_batch=(body.nomor_batch or "").strip() or None,
        tanggal_kedaluwarsa=body.tanggal_kedaluwarsa,
        qty_awal=body.qty,
        qty_sisa=body.qty,
        ingatkan_hari=body.ingatkan_hari,
    )
    db.add(batch)
    await db.commit()
    await db.refresh(batch)
    return BatchStokOut.model_validate(batch)


@router.delete("/{batch_id}", status_code=status.HTTP_204_NO_CONTENT)
async def hapus_batch(
    batch_id: uuid.UUID,
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> None:
    await _wajib_izin_stok(db, role_id)
    batch = await db.get(BatchStok, batch_id)
    if batch is None or batch.deleted_at is not None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Batch tidak ditemukan")
    await _outlet_milik_toko(db, batch.outlet_id, toko_id)
    await require_outlet_access(db, pengguna_id=pengguna_id, role_id=role_id, outlet_id=batch.outlet_id)

    from datetime import UTC, datetime

    batch.deleted_at = datetime.now(UTC)
    await db.commit()
