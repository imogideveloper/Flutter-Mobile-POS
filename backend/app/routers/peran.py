"""Peran dan hak akses (panduan IMOGI hlm. 28-30): peran bawaan sistem tidak bisa diubah; peran buatan
toko bisa dibuat, diubah, dan dihapus. Hanya izin yang dimiliki pelaku yang boleh diberikan, supaya
pemilik izin pengguna.kelola tidak bisa menaikkan hak aksesnya sendiri lewat peran baru."""

import uuid
from datetime import UTC, datetime

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import delete, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_db
from app.core.deps import get_pengguna_id, get_role_id, get_toko_id
from app.models.akun import Izin, Pengguna, Role, RoleIzin
from app.schemas.peran import IzinOut, PeranDetailOut, PeranIn, PeranUbahIn
from app.services.audit_service import catat_audit
from app.services.fitur_service import require_fitur
from app.services.izin_service import has_izin

router = APIRouter(tags=["peran"])


async def _wajib_kelola(db: AsyncSession, role_id: uuid.UUID) -> None:
    if not await has_izin(db, role_id, "pengguna.kelola"):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Role ini tidak punya izin pengguna.kelola")


async def _kode_izin_role(db: AsyncSession, role_id: uuid.UUID) -> list[str]:
    rows = await db.execute(
        select(Izin.kode).join(RoleIzin, RoleIzin.izin_id == Izin.id).where(RoleIzin.role_id == role_id).order_by(Izin.kode)
    )
    return list(rows.scalars().all())


async def _detail(db: AsyncSession, role: Role) -> PeranDetailOut:
    jumlah = await db.scalar(
        select(func.count()).select_from(Pengguna).where(Pengguna.role_id == role.id, Pengguna.deleted_at.is_(None))
    )
    return PeranDetailOut(
        id=role.id, nama=role.nama, is_system=role.is_system,
        izin_kode=await _kode_izin_role(db, role.id), jumlah_pengguna=jumlah or 0,
    )


async def _role_toko(db: AsyncSession, role_id: uuid.UUID, toko_id: uuid.UUID) -> Role:
    role = await db.get(Role, role_id)
    if role is None or role.deleted_at is not None or (not role.is_system and role.toko_id != toko_id):
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Role tidak ditemukan")
    return role


def _wajib_buatan_toko(role: Role) -> None:
    if role.is_system:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Peran bawaan tidak bisa diubah atau dihapus")


async def _pastikan_nama_unik(db: AsyncSession, toko_id: uuid.UUID, nama: str, kecuali: uuid.UUID | None = None) -> None:
    rows = await db.execute(
        select(Role.id, Role.nama).where(
            Role.deleted_at.is_(None), (Role.is_system.is_(True)) | (Role.toko_id == toko_id)
        )
    )
    for rid, nm in rows.all():
        if rid != kecuali and nm.strip().lower() == nama.strip().lower():
            raise HTTPException(status.HTTP_409_CONFLICT, "Nama peran sudah dipakai")


async def _izin_diizinkan(db: AsyncSession, role_id: uuid.UUID, kode: list[str]) -> list[Izin]:
    unik = sorted(set(kode))
    if not unik:
        return []
    ada = (await db.execute(select(Izin).where(Izin.kode.in_(unik)))).scalars().all()
    if {i.kode for i in ada} != set(unik):
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "Ada kode izin yang tidak dikenal")
    milik = set(await _kode_izin_role(db, role_id))
    if not set(unik) <= milik:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Tidak bisa memberi izin yang tidak dimiliki sendiri")
    return list(ada)


@router.get("/izin", response_model=list[IzinOut])
async def daftar_izin(_: uuid.UUID = Depends(get_toko_id), db: AsyncSession = Depends(get_db)) -> list[Izin]:
    return list((await db.execute(select(Izin).order_by(Izin.modul, Izin.kode))).scalars().all())


@router.get("/roles/{peran_id}", response_model=PeranDetailOut)
async def detail_peran(
    peran_id: uuid.UUID, toko_id: uuid.UUID = Depends(get_toko_id), db: AsyncSession = Depends(get_db)
) -> PeranDetailOut:
    return await _detail(db, await _role_toko(db, peran_id, toko_id))


@router.post(
    "/roles", response_model=PeranDetailOut, status_code=status.HTTP_201_CREATED,
    dependencies=[Depends(require_fitur("kelola_karyawan"))],
)
async def buat_peran(
    body: PeranIn,
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> PeranDetailOut:
    await _wajib_kelola(db, role_id)
    nama = body.nama.strip()
    if not nama:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "Nama peran wajib diisi")
    await _pastikan_nama_unik(db, toko_id, nama)
    izin = await _izin_diizinkan(db, role_id, body.izin_kode)
    role = Role(toko_id=toko_id, nama=nama, is_system=False)
    db.add(role)
    await db.flush()
    for i in izin:
        db.add(RoleIzin(role_id=role.id, izin_id=i.id))
    await catat_audit(
        db, toko_id=toko_id, pengguna_id=pengguna_id, aksi="tambah_peran", tabel="role", record_id=role.id,
        data_baru={"nama": nama, "izin": sorted(i.kode for i in izin)},
    )
    await db.commit()
    await db.refresh(role)
    return await _detail(db, role)


@router.patch(
    "/roles/{peran_id}", response_model=PeranDetailOut, dependencies=[Depends(require_fitur("kelola_karyawan"))]
)
async def ubah_peran(
    peran_id: uuid.UUID,
    body: PeranUbahIn,
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> PeranDetailOut:
    await _wajib_kelola(db, role_id)
    role = await _role_toko(db, peran_id, toko_id)
    _wajib_buatan_toko(role)
    lama = {"nama": role.nama, "izin": await _kode_izin_role(db, role.id)}
    if body.nama is not None:
        nama = body.nama.strip()
        if not nama:
            raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "Nama peran wajib diisi")
        await _pastikan_nama_unik(db, toko_id, nama, kecuali=role.id)
        role.nama = nama
    if body.izin_kode is not None:
        izin = await _izin_diizinkan(db, role_id, body.izin_kode)
        await db.execute(delete(RoleIzin).where(RoleIzin.role_id == role.id))
        for i in izin:
            db.add(RoleIzin(role_id=role.id, izin_id=i.id))
    role.updated_at = datetime.now(UTC)  # supaya /sync/pull membawa perubahan ke perangkat
    await db.flush()
    await catat_audit(
        db, toko_id=toko_id, pengguna_id=pengguna_id, aksi="ubah_peran", tabel="role", record_id=role.id,
        data_lama=lama, data_baru={"nama": role.nama, "izin": await _kode_izin_role(db, role.id)},
    )
    await db.commit()
    await db.refresh(role)
    return await _detail(db, role)


@router.delete(
    "/roles/{peran_id}", status_code=status.HTTP_204_NO_CONTENT, dependencies=[Depends(require_fitur("kelola_karyawan"))]
)
async def hapus_peran(
    peran_id: uuid.UUID,
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> None:
    await _wajib_kelola(db, role_id)
    role = await _role_toko(db, peran_id, toko_id)
    _wajib_buatan_toko(role)
    pakai = await db.scalar(
        select(func.count()).select_from(Pengguna).where(Pengguna.role_id == role.id, Pengguna.deleted_at.is_(None))
    )
    if pakai:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, f"Peran masih dipakai {pakai} karyawan")
    role.deleted_at = datetime.now(UTC)
    role.updated_at = role.deleted_at
    await catat_audit(
        db, toko_id=toko_id, pengguna_id=pengguna_id, aksi="hapus_peran", tabel="role", record_id=role.id,
        data_lama={"nama": role.nama},
    )
    await db.commit()
