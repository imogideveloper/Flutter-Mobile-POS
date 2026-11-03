"""Cek izin role (aturan dokumen #7: aksi sensitif wajib dicek izin role).
Pola sama dengan app Flutter (core/auth/pin_approval.dart) - server WAJIB
cek ulang, tidak percaya hasil cek di HP."""

import uuid

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.akun import Izin, RoleIzin


async def has_izin(db: AsyncSession, role_id: uuid.UUID, kode_izin: str) -> bool:
    result = await db.execute(
        select(RoleIzin)
        .join(Izin, Izin.id == RoleIzin.izin_id)
        .where(RoleIzin.role_id == role_id, Izin.kode == kode_izin)
    )
    return result.first() is not None
