"""Modul 3 (sebagian) - kategori, satuan, produk. Varian/modifier/resep/
harga_outlet/bundling/harga_grosir ada di router terpisah
(app/routers/produk_lanjutan.py) - dipisah supaya file ini tidak jadi
terlalu panjang."""

import uuid
from datetime import UTC, datetime

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_db
from app.core.deps import get_toko_id
from app.models.produk import Kategori, Produk, Satuan
from app.schemas.produk import (
    KategoriIn,
    KategoriOut,
    KategoriUpdateIn,
    ProdukIn,
    ProdukOut,
    ProdukUpdateIn,
    SatuanIn,
    SatuanOut,
)
from app.services.fitur_service import paket_efektif

router = APIRouter(tags=["produk"])


@router.get("/kategori", response_model=list[KategoriOut])
async def daftar_kategori(
    toko_id: uuid.UUID = Depends(get_toko_id), db: AsyncSession = Depends(get_db)
) -> list[Kategori]:
    rows = await db.execute(
        select(Kategori)
        .where(Kategori.toko_id == toko_id, Kategori.deleted_at.is_(None))
        .order_by(Kategori.urutan)
    )
    return list(rows.scalars().all())


@router.post("/kategori", response_model=KategoriOut, status_code=status.HTTP_201_CREATED)
async def tambah_kategori(
    body: KategoriIn, toko_id: uuid.UUID = Depends(get_toko_id), db: AsyncSession = Depends(get_db)
) -> Kategori:
    kategori = Kategori(toko_id=toko_id, **body.model_dump())
    db.add(kategori)
    await db.commit()
    await db.refresh(kategori)
    return kategori


async def _ambil_kategori_milik_toko(db: AsyncSession, kategori_id: uuid.UUID, toko_id: uuid.UUID) -> Kategori:
    kategori = await db.get(Kategori, kategori_id)
    if kategori is None or kategori.toko_id != toko_id or kategori.deleted_at is not None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Kategori tidak ditemukan")
    return kategori


@router.patch("/kategori/{kategori_id}", response_model=KategoriOut)
async def ubah_kategori(
    kategori_id: uuid.UUID,
    body: KategoriUpdateIn,
    toko_id: uuid.UUID = Depends(get_toko_id),
    db: AsyncSession = Depends(get_db),
) -> Kategori:
    kategori = await _ambil_kategori_milik_toko(db, kategori_id, toko_id)
    for field, value in body.model_dump(exclude_unset=True).items():
        setattr(kategori, field, value)
    await db.commit()
    await db.refresh(kategori)
    return kategori


@router.delete("/kategori/{kategori_id}", status_code=status.HTTP_204_NO_CONTENT)
async def hapus_kategori(
    kategori_id: uuid.UUID,
    toko_id: uuid.UUID = Depends(get_toko_id),
    db: AsyncSession = Depends(get_db),
) -> None:
    kategori = await _ambil_kategori_milik_toko(db, kategori_id, toko_id)
    # Produk yang masih menunjuk kategori ini DIBIARKAN (kategori_id jadi
    # "yatim" tapi tetap valid di ProdukOut - bukan di-null-kan paksa) -
    # sama prinsip dgn soft-delete di tabel lain (pajak dkk), histori
    # transaksi lama tidak boleh berubah makna krn master data dihapus.
    kategori.deleted_at = datetime.now(UTC)
    await db.commit()


@router.get("/satuan", response_model=list[SatuanOut])
async def daftar_satuan(
    toko_id: uuid.UUID = Depends(get_toko_id), db: AsyncSession = Depends(get_db)
) -> list[Satuan]:
    rows = await db.execute(
        select(Satuan).where(Satuan.toko_id == toko_id, Satuan.deleted_at.is_(None))
    )
    return list(rows.scalars().all())


@router.post("/satuan", response_model=SatuanOut, status_code=status.HTTP_201_CREATED)
async def tambah_satuan(
    body: SatuanIn, toko_id: uuid.UUID = Depends(get_toko_id), db: AsyncSession = Depends(get_db)
) -> Satuan:
    satuan = Satuan(toko_id=toko_id, **body.model_dump())
    db.add(satuan)
    await db.commit()
    await db.refresh(satuan)
    return satuan


@router.get("/produk", response_model=list[ProdukOut])
async def daftar_produk(
    toko_id: uuid.UUID = Depends(get_toko_id), db: AsyncSession = Depends(get_db)
) -> list[Produk]:
    rows = await db.execute(
        select(Produk).where(Produk.toko_id == toko_id, Produk.deleted_at.is_(None))
    )
    return list(rows.scalars().all())


async def _pastikan_kategori_satuan_milik_toko(
    db: AsyncSession, toko_id: uuid.UUID, kategori_id: uuid.UUID | None, satuan_id: uuid.UUID | None
) -> None:
    """kategori_id/satuan_id datang dari body klien - tanpa ini toko A bisa
    menautkan produknya ke kategori/satuan milik toko B (kebocoran nama
    kategori/satuan internal toko lain lewat ProdukOut)."""

    if kategori_id is not None:
        kategori = await db.get(Kategori, kategori_id)
        if kategori is None or kategori.toko_id != toko_id:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Kategori tidak ditemukan")
    if satuan_id is not None:
        satuan = await db.get(Satuan, satuan_id)
        if satuan is None or satuan.toko_id != toko_id:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Satuan tidak ditemukan")


async def _pastikan_kuota_produk(db: AsyncSession, toko_id: uuid.UUID) -> None:
    """Temuan#3 (rapikan F3) - `paket.maks_produk` sebelumnya cuma
    ditampilkan di halaman Paket langganan (F3.F), TIDAK PERNAH ditegakkan
    di sini - gap nyata, bukan cuma lupa dites. Produk yang di-soft-delete
    (deleted_at terisi) TIDAK dihitung, sama konvensi dgn kuota pengguna."""

    paket = await paket_efektif(db, toko_id)
    if paket.maks_produk is None:
        return
    jumlah_sekarang = await db.scalar(
        select(func.count()).select_from(Produk).where(Produk.toko_id == toko_id, Produk.deleted_at.is_(None))
    )
    if jumlah_sekarang + 1 > paket.maks_produk:
        raise HTTPException(
            status.HTTP_403_FORBIDDEN,
            detail={"kode": "kuota_habis", "jenis": "produk", "batas": paket.maks_produk},
        )


@router.post("/produk", response_model=ProdukOut, status_code=status.HTTP_201_CREATED)
async def tambah_produk(
    body: ProdukIn, toko_id: uuid.UUID = Depends(get_toko_id), db: AsyncSession = Depends(get_db)
) -> Produk:
    await _pastikan_kategori_satuan_milik_toko(db, toko_id, body.kategori_id, body.satuan_id)
    await _pastikan_kuota_produk(db, toko_id)
    produk = Produk(toko_id=toko_id, **body.model_dump())
    db.add(produk)
    await db.commit()
    await db.refresh(produk)
    return produk


async def ambil_produk_milik_toko(produk_id: uuid.UUID, toko_id: uuid.UUID, db: AsyncSession) -> Produk:
    produk = await db.get(Produk, produk_id)
    if produk is None or produk.toko_id != toko_id or produk.deleted_at is not None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Produk tidak ditemukan")
    return produk


@router.get("/produk/{produk_id}", response_model=ProdukOut)
async def detail_produk(
    produk_id: uuid.UUID,
    toko_id: uuid.UUID = Depends(get_toko_id),
    db: AsyncSession = Depends(get_db),
) -> Produk:
    return await ambil_produk_milik_toko(produk_id, toko_id, db)


@router.patch("/produk/{produk_id}", response_model=ProdukOut)
async def ubah_produk(
    produk_id: uuid.UUID,
    body: ProdukUpdateIn,
    toko_id: uuid.UUID = Depends(get_toko_id),
    db: AsyncSession = Depends(get_db),
) -> Produk:
    produk = await ambil_produk_milik_toko(produk_id, toko_id, db)
    updated = body.model_dump(exclude_unset=True)
    await _pastikan_kategori_satuan_milik_toko(
        db, toko_id, updated.get("kategori_id"), updated.get("satuan_id")
    )
    for field, value in updated.items():
        setattr(produk, field, value)
    await db.commit()
    await db.refresh(produk)
    return produk


@router.delete("/produk/{produk_id}", status_code=status.HTTP_204_NO_CONTENT)
async def hapus_produk(
    produk_id: uuid.UUID,
    toko_id: uuid.UUID = Depends(get_toko_id),
    db: AsyncSession = Depends(get_db),
) -> None:
    produk = await ambil_produk_milik_toko(produk_id, toko_id, db)
    produk.deleted_at = datetime.now(UTC)
    await db.commit()
