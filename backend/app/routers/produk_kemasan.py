"""Kemasan jual produk (IMOGI no. 43): mis. 1 dus = 12 pcs dengan harga sendiri.

Stok tetap di satuan dasar produk. Kemasan hanya mengalikan jumlah (isi) dan punya harga sendiri;
penjualan per kemasan dicatat di baris transaksi (`isi_kemasan`, `nama_kemasan`)."""

import uuid
from datetime import UTC, datetime

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_db
from app.core.deps import get_role_id, get_toko_id
from app.models.produk import Produk, ProdukKemasan
from app.services.fitur_service import require_fitur
from app.services.izin_service import has_izin

router = APIRouter(tags=["produk-kemasan"])


class KemasanIn(BaseModel):
    nama: str = Field(min_length=1, max_length=50)
    isi: float = Field(gt=1, le=1_000_000)
    harga: float = Field(ge=0)


class KemasanUpdateIn(BaseModel):
    nama: str | None = Field(default=None, min_length=1, max_length=50)
    isi: float | None = Field(default=None, gt=1, le=1_000_000)
    harga: float | None = Field(default=None, ge=0)


class KemasanOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    produk_id: uuid.UUID
    nama: str
    isi: float
    harga: float


async def _wajib_izin_produk(db: AsyncSession, role_id: uuid.UUID) -> None:
    if not await has_izin(db, role_id, "produk.kelola"):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Role ini tidak punya izin produk.kelola")


async def _produk_milik_toko(db: AsyncSession, produk_id: uuid.UUID, toko_id: uuid.UUID) -> Produk:
    produk = await db.get(Produk, produk_id)
    if produk is None or produk.toko_id != toko_id or produk.deleted_at is not None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Produk tidak ditemukan")
    return produk


async def _kemasan_milik_toko(db: AsyncSession, kemasan_id: uuid.UUID, toko_id: uuid.UUID) -> ProdukKemasan:
    kemasan = await db.get(ProdukKemasan, kemasan_id)
    if kemasan is None or kemasan.toko_id != toko_id or kemasan.deleted_at is not None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Kemasan tidak ditemukan")
    return kemasan


async def _pastikan_nama_unik(
    db: AsyncSession, produk_id: uuid.UUID, nama: str, kecuali: uuid.UUID | None = None
) -> None:
    ada = (
        await db.execute(
            select(ProdukKemasan).where(
                ProdukKemasan.produk_id == produk_id,
                ProdukKemasan.nama == nama,
                ProdukKemasan.deleted_at.is_(None),
            )
        )
    ).scalars().all()
    if any(k.id != kecuali for k in ada):
        raise HTTPException(status.HTTP_409_CONFLICT, f"Kemasan '{nama}' sudah ada untuk produk ini")


@router.get("/produk/{produk_id}/kemasan", response_model=list[KemasanOut])
async def daftar_kemasan(
    produk_id: uuid.UUID, toko_id: uuid.UUID = Depends(get_toko_id), db: AsyncSession = Depends(get_db)
) -> list[KemasanOut]:
    await _produk_milik_toko(db, produk_id, toko_id)
    rows = (
        await db.execute(
            select(ProdukKemasan)
            .where(ProdukKemasan.produk_id == produk_id, ProdukKemasan.deleted_at.is_(None))
            .order_by(ProdukKemasan.isi.asc())
        )
    ).scalars().all()
    return [KemasanOut.model_validate(r) for r in rows]


@router.post(
    "/produk/{produk_id}/kemasan",
    response_model=KemasanOut,
    status_code=status.HTTP_201_CREATED,
    dependencies=[Depends(require_fitur("pack_units"))],
)
async def tambah_kemasan(
    produk_id: uuid.UUID,
    body: KemasanIn,
    toko_id: uuid.UUID = Depends(get_toko_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> KemasanOut:
    await _wajib_izin_produk(db, role_id)
    await _produk_milik_toko(db, produk_id, toko_id)
    nama = body.nama.strip()
    if not nama:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, "Nama kemasan wajib diisi")
    await _pastikan_nama_unik(db, produk_id, nama)
    kemasan = ProdukKemasan(toko_id=toko_id, produk_id=produk_id, nama=nama, isi=body.isi, harga=body.harga)
    db.add(kemasan)
    await db.commit()
    await db.refresh(kemasan)
    return KemasanOut.model_validate(kemasan)


@router.patch("/kemasan/{kemasan_id}", response_model=KemasanOut)
async def ubah_kemasan(
    kemasan_id: uuid.UUID,
    body: KemasanUpdateIn,
    toko_id: uuid.UUID = Depends(get_toko_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> KemasanOut:
    await _wajib_izin_produk(db, role_id)
    kemasan = await _kemasan_milik_toko(db, kemasan_id, toko_id)
    if body.nama is not None:
        nama = body.nama.strip()
        if not nama:
            raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, "Nama kemasan wajib diisi")
        await _pastikan_nama_unik(db, kemasan.produk_id, nama, kecuali=kemasan.id)
        kemasan.nama = nama
    if body.isi is not None:
        kemasan.isi = body.isi
    if body.harga is not None:
        kemasan.harga = body.harga
    await db.commit()
    await db.refresh(kemasan)
    return KemasanOut.model_validate(kemasan)


@router.delete("/kemasan/{kemasan_id}", status_code=status.HTTP_204_NO_CONTENT)
async def hapus_kemasan(
    kemasan_id: uuid.UUID,
    toko_id: uuid.UUID = Depends(get_toko_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> None:
    await _wajib_izin_produk(db, role_id)
    kemasan = await _kemasan_milik_toko(db, kemasan_id, toko_id)
    kemasan.deleted_at = datetime.now(UTC)
    await db.commit()
