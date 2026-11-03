"""Audit log read-only (aturan dokumen #7: aksi sensitif dicatat di
audit_log - void/refund/sync sudah menulis ke sini, ini cuma bacanya).
Digating `laporan.lihat` (bukan izin khusus audit - dokumen tidak punya
kode izin tersendiri utk ini) supaya Kasir (yang hanya punya
transaksi.buat/shift.buka_tutup/kas.keluar_masuk/pelanggan.kelola) tidak
bisa intip jejak aksi sensitif orang lain, tapi Owner/Manajer bisa."""

import uuid
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_db
from app.core.deps import get_role_id, get_toko_id
from app.models.audit import AuditLog
from app.schemas.audit import AuditLogOut
from app.services.izin_service import has_izin

router = APIRouter(tags=["audit"])


@router.get("/audit-log", response_model=list[AuditLogOut])
async def daftar_audit_log(
    tabel: str | None = Query(None),
    record_id: uuid.UUID | None = Query(None),
    sejak: datetime | None = Query(None),
    # Temuan#2 (rapikan F3.E) - filter `aksi` dipakai laporan owner "daftar
    # pesanan dibatalkan per kasir": GET /audit-log?tabel=transaksi&aksi=
    # batalkan_pesanan_tersimpan, lalu dikelompokkan client-side per
    # pengguna_id (sudah ada di AuditLogOut) - bukan endpoint laporan baru.
    aksi: str | None = Query(None),
    limit: int = Query(50, ge=1, le=200),
    toko_id: uuid.UUID = Depends(get_toko_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> list[AuditLog]:
    if not await has_izin(db, role_id, "laporan.lihat"):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Role ini tidak punya izin laporan.lihat")

    query = select(AuditLog).where(AuditLog.toko_id == toko_id)
    if tabel is not None:
        query = query.where(AuditLog.tabel == tabel)
    if record_id is not None:
        query = query.where(AuditLog.record_id == record_id)
    if aksi is not None:
        query = query.where(AuditLog.aksi == aksi)
    if sejak is not None:
        query = query.where(AuditLog.created_at >= sejak)

    rows = (
        await db.execute(query.order_by(AuditLog.created_at.desc()).limit(limit))
    ).scalars().all()
    return list(rows)
