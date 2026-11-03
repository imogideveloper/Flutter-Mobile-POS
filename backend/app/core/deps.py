"""Dependency FastAPI yang konsisten dipakai di SEMUA router: autentikasi,
dan - yang terpenting - penentuan `toko_id` dari token (bukan dari body
request). Lihat aturan dokumen #6: setiap query backend wajib difilter
toko_id dari token login."""

import uuid
from collections.abc import Sequence

from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from .db import get_db
from .security import InvalidTokenError, TokenClaims, decode_token

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/auth/otp/verify", auto_error=False)


def get_current_claims(token: str | None = Depends(oauth2_scheme)) -> TokenClaims:
    if token is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Token tidak ditemukan")
    try:
        return decode_token(token, expected_type="access")
    except InvalidTokenError as exc:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, f"Token tidak valid: {exc}") from exc


def get_toko_id(claims: TokenClaims = Depends(get_current_claims)) -> uuid.UUID:
    return claims.toko_id


def get_pengguna_id(claims: TokenClaims = Depends(get_current_claims)) -> uuid.UUID:
    return claims.pengguna_id


def get_role_id(claims: TokenClaims = Depends(get_current_claims)) -> uuid.UUID:
    return claims.role_id


async def get_accessible_outlet_ids(
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    db: AsyncSession = Depends(get_db),
) -> Sequence[uuid.UUID]:
    from app.models.akun import AksesOutlet  # import lokal - hindari circular import

    rows = await db.execute(select(AksesOutlet.outlet_id).where(AksesOutlet.pengguna_id == pengguna_id))
    return [row[0] for row in rows.all()]


async def require_outlet_access(
    db: AsyncSession, *, pengguna_id: uuid.UUID, role_id: uuid.UUID, outlet_id: uuid.UUID
) -> None:
    """Hak akses outlet SATU TINGKAT LEBIH SEMPIT dari kepemilikan toko
    (lihat app/services/kepemilikan.py - itu cuma mastikan outlet milik
    toko yang login, BUKAN mastikan pengguna yang login boleh pakai outlet
    itu). Owner/Manajer selalu boleh semua outlet DI TOKONYA (pembatasan
    toko-nya sendiri tetap wajib dicek terpisah lewat kepemilikan.py di
    pemanggil) - Kasir dkk HANYA boleh outlet yang ada di baris
    `akses_outlet` miliknya.

    Dipanggil EXPLICIT dari router/service (bukan `Depends()` sbg
    sub-dependency) krn `outlet_id` di banyak endpoint datang dari body
    JSON (checkout, buka shift, pembelian, dst), bukan cuma path/query -
    FastAPI tidak bisa auto-resolve nama dependency dari field body
    sewenang-wenang, jadi dipanggil manual persis seperti helper
    kepemilikan.py yang sudah ada."""

    from app.models.akun import Role  # import lokal - hindari circular import

    role = await db.get(Role, role_id)
    if role is not None and role.is_system and role.nama in ("Owner", "Manajer"):
        return

    accessible = await get_accessible_outlet_ids(pengguna_id=pengguna_id, db=db)
    if outlet_id not in accessible:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Tidak punya akses ke outlet ini")
