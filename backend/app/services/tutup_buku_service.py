"""Penegakan tutup buku (IMOGI no. 78): pencatatan bertanggal pada/sebelum tanggal tutup ditolak (HTTP 409)."""

import uuid
from datetime import date

from fastapi import HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.tutup_buku import TutupBuku


async def tanggal_tutup(db: AsyncSession, toko_id: uuid.UUID) -> date | None:
    """Tanggal terakhir yang sudah ditutup, atau None bila belum pernah tutup buku."""
    return (
        await db.execute(
            select(func.max(TutupBuku.sampai)).where(TutupBuku.toko_id == toko_id, TutupBuku.deleted_at.is_(None))
        )
    ).scalar_one_or_none()


async def pastikan_periode_terbuka(db: AsyncSession, toko_id: uuid.UUID, tanggal: date) -> None:
    tutup = await tanggal_tutup(db, toko_id)
    if tutup is not None and tanggal <= tutup:
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            f"Pembukuan sampai {tutup.isoformat()} sudah ditutup; tanggal {tanggal.isoformat()} tidak bisa diubah",
        )
