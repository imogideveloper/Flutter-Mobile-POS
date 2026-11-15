"""Login akun Administrator Imogi + pembuatan akun admin pertama.

POST /admin/auth/login  - email+password -> JWT admin (tipe 'admin').
GET  /admin/auth/saya   - identitas admin yang sedang login.
POST /admin/akun        - buat akun admin; HANYA lewat API key statis (jalur
                          bootstrap: belum ada admin pertama untuk login)."""

import uuid
from datetime import UTC, datetime

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.admin_auth import verifikasi_admin, verifikasi_admin_api_key
from app.core.db import get_db
from app.core.security import create_admin_token, hash_password, verify_password
from app.models.platform import AkunAdmin

router = APIRouter(tags=["admin"])


class AdminLoginIn(BaseModel):
    email: str
    password: str


class AdminTokenOut(BaseModel):
    access_token: str
    token_type: str = "bearer"


class AdminOut(BaseModel):
    id: uuid.UUID
    email: str
    nama: str

    model_config = {"from_attributes": True}


class AdminBaruIn(BaseModel):
    email: str = Field(min_length=5, max_length=150)
    nama: str = Field(min_length=1, max_length=100)
    password: str = Field(min_length=10, max_length=100)


@router.post("/admin/auth/login", response_model=AdminTokenOut)
async def login_admin(body: AdminLoginIn, db: AsyncSession = Depends(get_db)) -> AdminTokenOut:
    akun = (
        await db.execute(select(AkunAdmin).where(func.lower(AkunAdmin.email) == body.email.strip().lower()))
    ).scalar_one_or_none()
    # Pesan sama utk email salah/password salah/akun nonaktif (tidak bocorkan mana yang benar).
    if akun is None or not akun.aktif or not verify_password(body.password, akun.password_hash):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Email atau password salah")
    akun.terakhir_login = datetime.now(UTC)
    await db.commit()
    return AdminTokenOut(access_token=create_admin_token(admin_id=akun.id))


@router.get("/admin/auth/saya", response_model=AdminOut)
async def admin_saya(
    admin_id: uuid.UUID | None = Depends(verifikasi_admin), db: AsyncSession = Depends(get_db)
) -> AkunAdmin:
    if admin_id is None:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Endpoint ini butuh login administrator")
    return await db.get(AkunAdmin, admin_id)


@router.post(
    "/admin/akun",
    response_model=AdminOut,
    status_code=status.HTTP_201_CREATED,
    dependencies=[Depends(verifikasi_admin_api_key)],
)
async def buat_akun_admin(body: AdminBaruIn, db: AsyncSession = Depends(get_db)) -> AkunAdmin:
    email = body.email.strip().lower()
    ada = (await db.execute(select(AkunAdmin).where(func.lower(AkunAdmin.email) == email))).scalar_one_or_none()
    if ada is not None:
        raise HTTPException(status.HTTP_409_CONFLICT, "Email admin sudah terdaftar")
    akun = AkunAdmin(email=email, nama=body.nama.strip(), password_hash=hash_password(body.password))
    db.add(akun)
    await db.commit()
    await db.refresh(akun)
    return akun
