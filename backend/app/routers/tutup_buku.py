"""Tutup buku (IMOGI no. 78): Owner mengunci pembukuan sampai tanggal tertentu.

Setelah ditutup, pengeluaran, settlement, dan anggaran bertanggal pada/sebelum tanggal tutup tidak bisa
dicatat, diubah, atau dihapus. Transaksi penjualan TIDAK dikunci (kasir offline masih mengirim data lama);
koreksinya dicatat di periode berjalan. Owner bisa membuka kembali penutupan terakhir."""

import uuid
from datetime import UTC, date, datetime

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_db
from app.core.deps import get_pengguna_id, get_role_id, get_toko_id
from app.models.akun import Role
from app.models.tutup_buku import TutupBuku
from app.services.audit_service import catat_audit
from app.services.fitur_service import require_fitur
from app.services.izin_service import has_izin
from app.services.tutup_buku_service import tanggal_tutup

router = APIRouter(prefix="/tutup-buku", tags=["tutup-buku"], dependencies=[Depends(require_fitur("year_end_closing"))])


class TutupIn(BaseModel):
    sampai: date
    catatan: str | None = Field(default=None, max_length=500)


class RiwayatOut(BaseModel):
    id: uuid.UUID
    sampai: date
    catatan: str | None
    dibuat: datetime


class StatusTutupOut(BaseModel):
    ditutup_sampai: date | None
    riwayat: list[RiwayatOut]


async def _wajib_owner(db: AsyncSession, role_id: uuid.UUID) -> None:
    role = await db.get(Role, role_id)
    if not (role is not None and role.is_system and role.nama == "Owner"):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Tutup buku hanya untuk Owner")


async def _status(db: AsyncSession, toko_id: uuid.UUID) -> StatusTutupOut:
    rows = (
        await db.execute(
            select(TutupBuku)
            .where(TutupBuku.toko_id == toko_id, TutupBuku.deleted_at.is_(None))
            .order_by(TutupBuku.sampai.desc(), TutupBuku.created_at.desc())
        )
    ).scalars().all()
    return StatusTutupOut(
        ditutup_sampai=await tanggal_tutup(db, toko_id),
        riwayat=[RiwayatOut(id=r.id, sampai=r.sampai, catatan=r.catatan, dibuat=r.created_at) for r in rows],
    )


@router.get("", response_model=StatusTutupOut)
async def lihat_status(
    toko_id: uuid.UUID = Depends(get_toko_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> StatusTutupOut:
    if not await has_izin(db, role_id, "laporan.lihat"):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Role ini tidak punya izin laporan.lihat")
    return await _status(db, toko_id)


@router.post("", response_model=StatusTutupOut, status_code=status.HTTP_201_CREATED)
async def tutup_buku(
    body: TutupIn,
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> StatusTutupOut:
    await _wajib_owner(db, role_id)
    hari_ini = datetime.now(UTC).date()
    if body.sampai > hari_ini:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, "Tidak bisa menutup buku untuk tanggal yang belum lewat")
    sekarang = await tanggal_tutup(db, toko_id)
    if sekarang is not None and body.sampai <= sekarang:
        raise HTTPException(
            status.HTTP_409_CONFLICT, f"Pembukuan sudah ditutup sampai {sekarang.isoformat()}; pilih tanggal yang lebih baru"
        )
    baris = TutupBuku(
        toko_id=toko_id, sampai=body.sampai, ditutup_oleh=pengguna_id, catatan=(body.catatan or "").strip() or None
    )
    db.add(baris)
    await db.flush()
    await catat_audit(
        db, toko_id=toko_id, pengguna_id=pengguna_id, aksi="tutup_buku", tabel="tutup_buku", record_id=baris.id,
        data_baru={"sampai": body.sampai.isoformat()},
    )
    await db.commit()
    return await _status(db, toko_id)


@router.delete("/terakhir", response_model=StatusTutupOut)
async def buka_kembali(
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> StatusTutupOut:
    await _wajib_owner(db, role_id)
    terakhir = (
        await db.execute(
            select(TutupBuku)
            .where(TutupBuku.toko_id == toko_id, TutupBuku.deleted_at.is_(None))
            .order_by(TutupBuku.sampai.desc(), TutupBuku.created_at.desc())
            .limit(1)
        )
    ).scalar_one_or_none()
    if terakhir is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Belum ada penutupan buku")
    terakhir.deleted_at = datetime.now(UTC)
    await catat_audit(
        db, toko_id=toko_id, pengguna_id=pengguna_id, aksi="buka_kembali_buku", tabel="tutup_buku",
        record_id=terakhir.id, data_lama={"sampai": terakhir.sampai.isoformat()},
    )
    await db.commit()
    return await _status(db, toko_id)
