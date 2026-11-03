"""Pencatatan audit_log - dipanggil setiap aksi sensitif (aturan dokumen
#7): void, refund, diskon manual, ubah harga, hapus produk, login, approve."""

import uuid
from typing import Any

from sqlalchemy.ext.asyncio import AsyncSession

from app.models.audit import AuditLog


async def catat_audit(
    db: AsyncSession,
    *,
    toko_id: uuid.UUID | None,
    pengguna_id: uuid.UUID | None,
    aksi: str,
    tabel: str | None = None,
    record_id: uuid.UUID | None = None,
    data_lama: dict[str, Any] | None = None,
    data_baru: dict[str, Any] | None = None,
) -> None:
    db.add(
        AuditLog(
            toko_id=toko_id,
            pengguna_id=pengguna_id,
            aksi=aksi,
            tabel=tabel,
            record_id=record_id,
            data_lama=data_lama,
            data_baru=data_baru,
        )
    )
