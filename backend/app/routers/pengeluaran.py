"""Pengeluaran & biaya operasional (IMOGI no. 67, fitur `expenses`, paket Starter).

Hak akses memakai izin `laporan.lihat` (Owner/Manajer): pencatatan biaya bersifat keuangan.
"""

import uuid
from datetime import UTC, date, datetime

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_db
from app.core.deps import get_pengguna_id, get_role_id, get_toko_id
from app.models.outlet import Outlet
from app.models.pengeluaran import Pengeluaran
from app.schemas.pengeluaran import DaftarPengeluaranOut, PengeluaranIn, PengeluaranOut, RingkasanKategoriOut
from app.services.audit_service import catat_audit
from app.services.fitur_service import require_fitur
from app.services.izin_service import has_izin

router = APIRouter(
    prefix="/pengeluaran", tags=["pengeluaran"], dependencies=[Depends(require_fitur("expenses"))]
)


async def _wajib_izin(db: AsyncSession, role_id: uuid.UUID) -> None:
    if not await has_izin(db, role_id, "laporan.lihat"):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Tidak punya izin mengelola pengeluaran")


@router.get("", response_model=DaftarPengeluaranOut)
async def daftar_pengeluaran(
    dari: date = Query(...),
    sampai: date = Query(...),
    toko_id: uuid.UUID = Depends(get_toko_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> DaftarPengeluaranOut:
    await _wajib_izin(db, role_id)
    if sampai < dari:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Tanggal sampai lebih awal dari dari")
    rows = (
        await db.execute(
            select(Pengeluaran)
            .where(
                Pengeluaran.toko_id == toko_id,
                Pengeluaran.deleted_at.is_(None),
                Pengeluaran.tanggal >= dari,
                Pengeluaran.tanggal <= sampai,
            )
            .order_by(Pengeluaran.tanggal.desc(), Pengeluaran.created_at.desc())
        )
    ).scalars().all()
    per_kategori: dict[str, float] = {}
    for r in rows:
        per_kategori[r.kategori] = per_kategori.get(r.kategori, 0.0) + float(r.jumlah)
    return DaftarPengeluaranOut(
        total=sum(per_kategori.values()),
        per_kategori=[
            RingkasanKategoriOut(kategori=k, total=v)
            for k, v in sorted(per_kategori.items(), key=lambda kv: -kv[1])
        ],
        item=[PengeluaranOut.model_validate(r) for r in rows],
    )


@router.post("", response_model=PengeluaranOut, status_code=status.HTTP_201_CREATED)
async def catat_pengeluaran(
    body: PengeluaranIn,
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> Pengeluaran:
    await _wajib_izin(db, role_id)
    if body.id is not None:
        ada = await db.get(Pengeluaran, body.id)
        if ada is not None:
            if ada.toko_id != toko_id:
                raise HTTPException(status.HTTP_409_CONFLICT, "ID pengeluaran tidak tersedia")
            return ada  # kirim ulang yang sama: idempoten
    if body.outlet_id is not None:
        outlet = await db.get(Outlet, body.outlet_id)
        if outlet is None or outlet.toko_id != toko_id:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Outlet tidak ditemukan")

    baris = Pengeluaran(
        toko_id=toko_id,
        outlet_id=body.outlet_id,
        tanggal=body.tanggal,
        kategori=body.kategori,
        jumlah=body.jumlah,
        catatan=body.catatan,
        dibuat_oleh=pengguna_id,
    )
    if body.id is not None:
        baris.id = body.id
    db.add(baris)
    await db.flush()
    await catat_audit(
        db, toko_id=toko_id, pengguna_id=pengguna_id, aksi="catat_pengeluaran",
        tabel="pengeluaran", record_id=baris.id,
        data_baru={"kategori": body.kategori, "jumlah": str(body.jumlah)},
    )
    await db.commit()
    await db.refresh(baris)
    return baris


@router.delete("/{pengeluaran_id}", status_code=status.HTTP_204_NO_CONTENT)
async def hapus_pengeluaran(
    pengeluaran_id: uuid.UUID,
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> None:
    await _wajib_izin(db, role_id)
    baris = await db.get(Pengeluaran, pengeluaran_id)
    if baris is None or baris.toko_id != toko_id or baris.deleted_at is not None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Pengeluaran tidak ditemukan")
    baris.deleted_at = datetime.now(UTC)
    await catat_audit(
        db, toko_id=toko_id, pengguna_id=pengguna_id, aksi="hapus_pengeluaran",
        tabel="pengeluaran", record_id=baris.id,
        data_lama={"kategori": baris.kategori, "jumlah": str(baris.jumlah)},
    )
    await db.commit()
