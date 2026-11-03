"""JWT access+refresh token dan hashing password/PIN.

Klaim token SELALU berisi `toko_id` - inilah satu-satunya sumber `toko_id`
yang dipercaya backend (aturan dokumen #6: tidak ada endpoint yang menerima
toko_id dari body untuk menentukan akses)."""

import uuid
from datetime import UTC, datetime, timedelta
from typing import Any, Literal

import bcrypt
from jose import JWTError, jwt

from .config import get_settings

# bcrypt langsung (BUKAN passlib.CryptContext) - passlib 1.7.4 punya
# self-test internal (detect_wrap_bug) yang crash di bcrypt>=4 (API
# __about__ dihapus, ValueError dilempar utk secret >72 byte bukan
# di-truncate). Dipakai dari lib resminya langsung, lebih sederhana & tidak
# terikat ke passlib yang sudah lama tidak dirawat utk versi bcrypt baru.
TokenType = Literal["access", "refresh"]


class TokenClaims:
    def __init__(
        self,
        *,
        pengguna_id: uuid.UUID,
        toko_id: uuid.UUID,
        role_id: uuid.UUID,
        token_type: TokenType,
        perangkat_id: uuid.UUID | None = None,
    ):
        self.pengguna_id = pengguna_id
        self.toko_id = toko_id
        self.role_id = role_id
        self.token_type = token_type
        # Tahap 5b - "token per karyawan terikat ke perangkat". Opsional
        # (None utk token lama/yang belum di-reissue) supaya tidak
        # memaksa migrasi serentak semua jalur pembuatan token.
        self.perangkat_id = perangkat_id


def hash_password(raw: str) -> str:
    return bcrypt.hashpw(raw.encode("utf-8"), bcrypt.gensalt()).decode("ascii")


def verify_password(raw: str, hashed: str) -> bool:
    return bcrypt.checkpw(raw.encode("utf-8"), hashed.encode("ascii"))


def _create_token(
    *,
    pengguna_id: uuid.UUID,
    toko_id: uuid.UUID,
    role_id: uuid.UUID,
    token_type: TokenType,
    expires_delta: timedelta,
    perangkat_id: uuid.UUID | None = None,
) -> str:
    settings = get_settings()
    now = datetime.now(UTC)
    payload: dict[str, Any] = {
        "sub": str(pengguna_id),
        "toko_id": str(toko_id),
        "role_id": str(role_id),
        "type": token_type,
        "iat": now,
        "exp": now + expires_delta,
    }
    if perangkat_id is not None:
        payload["perangkat_id"] = str(perangkat_id)
    return jwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_algorithm)


def create_access_token(
    *, pengguna_id: uuid.UUID, toko_id: uuid.UUID, role_id: uuid.UUID, perangkat_id: uuid.UUID | None = None
) -> str:
    settings = get_settings()
    return _create_token(
        pengguna_id=pengguna_id,
        toko_id=toko_id,
        role_id=role_id,
        token_type="access",
        expires_delta=timedelta(minutes=settings.access_token_expire_minutes),
        perangkat_id=perangkat_id,
    )


def create_refresh_token(
    *, pengguna_id: uuid.UUID, toko_id: uuid.UUID, role_id: uuid.UUID, perangkat_id: uuid.UUID | None = None
) -> str:
    settings = get_settings()
    return _create_token(
        pengguna_id=pengguna_id,
        toko_id=toko_id,
        role_id=role_id,
        token_type="refresh",
        expires_delta=timedelta(days=settings.refresh_token_expire_days),
        perangkat_id=perangkat_id,
    )


class InvalidTokenError(Exception):
    pass


def decode_token(token: str, *, expected_type: TokenType) -> TokenClaims:
    settings = get_settings()
    try:
        payload = jwt.decode(token, settings.jwt_secret, algorithms=[settings.jwt_algorithm])
    except JWTError as exc:
        raise InvalidTokenError(str(exc)) from exc

    if payload.get("type") != expected_type:
        raise InvalidTokenError(f"Diharapkan token tipe {expected_type}, didapat {payload.get('type')}")

    try:
        return TokenClaims(
            pengguna_id=uuid.UUID(payload["sub"]),
            toko_id=uuid.UUID(payload["toko_id"]),
            role_id=uuid.UUID(payload["role_id"]),
            token_type=payload["type"],
            perangkat_id=uuid.UUID(payload["perangkat_id"]) if payload.get("perangkat_id") else None,
        )
    except (KeyError, ValueError) as exc:
        raise InvalidTokenError("Klaim token tidak lengkap/tidak valid") from exc
