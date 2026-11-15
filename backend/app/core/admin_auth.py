"""Autentikasi ADMIN platform (bukan owner toko; admin tidak punya
toko_id/role_id).

Dua jalur, keduanya sah:
1. JWT akun Administrator (`Authorization: Bearer`, dari POST /admin/auth/login)
   - jalur utama untuk dashboard admin.
2. API key statis `X-Admin-Api-Key` (Settings.admin_api_key, default KOSONG =
   selalu menolak) - jalur peralihan/darurat, juga satu-satunya cara membuat
   akun Administrator PERTAMA (lihat routers/admin_auth.py)."""

import uuid

from fastapi import Depends, Header, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.ext.asyncio import AsyncSession

from .config import get_settings
from .db import get_db
from .security import InvalidTokenError, decode_admin_token

_admin_scheme = OAuth2PasswordBearer(tokenUrl="/admin/auth/login", auto_error=False)


def _api_key_valid(x_admin_api_key: str | None) -> bool:
    settings = get_settings()
    return bool(settings.admin_api_key) and x_admin_api_key == settings.admin_api_key


def verifikasi_admin_api_key(x_admin_api_key: str | None = Header(default=None)) -> None:
    if not _api_key_valid(x_admin_api_key):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Admin API key tidak valid")


async def verifikasi_admin(
    token: str | None = Depends(_admin_scheme),
    x_admin_api_key: str | None = Header(default=None),
    db: AsyncSession = Depends(get_db),
) -> uuid.UUID | None:
    """Mengembalikan id akun admin bila lewat JWT, None bila lewat API key."""
    from app.models.platform import AkunAdmin  # import lokal - hindari circular import

    if token is not None:
        try:
            admin_id = decode_admin_token(token)
        except InvalidTokenError as exc:
            raise HTTPException(status.HTTP_401_UNAUTHORIZED, f"Token admin tidak valid: {exc}") from exc
        akun = await db.get(AkunAdmin, admin_id)
        if akun is None or not akun.aktif:
            raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Akun admin tidak aktif")
        return admin_id
    if _api_key_valid(x_admin_api_key):
        return None
    raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Butuh login administrator atau admin API key")
