"""Modul 2: Pengguna & hak akses. Role custom-per-toko (bukan 3 role
bawaan sistem) belum ada endpoint create-nya (TODO) - saat ini cuma bisa
pilih dari role bawaan (Owner/Manajer/Kasir) + role yang sudah ada."""

import uuid
from datetime import UTC, datetime

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import delete, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_db
from app.core.deps import get_pengguna_id, get_role_id, get_toko_id
from app.core.security import hash_password
from app.models.akun import AksesOutlet, Pengguna, Role
from app.models.outlet import Outlet
from app.schemas.pengguna import PenggunaIn, PenggunaOut, PenggunaUpdateIn, ResetPinIn, RoleOut
from app.services.audit_service import catat_audit
from app.services.fitur_service import paket_efektif
from app.services.izin_service import has_izin


async def _pastikan_role_milik_toko(db: AsyncSession, role_id: uuid.UUID, toko_id: uuid.UUID) -> Role:
    role = await db.get(Role, role_id)
    if role is None or (not role.is_system and role.toko_id != toko_id):
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Role tidak ditemukan")
    return role


async def _pastikan_outlet_ids_milik_toko(
    db: AsyncSession, outlet_ids: list[uuid.UUID], toko_id: uuid.UUID
) -> None:
    outlet_ids_set = set(outlet_ids)
    if not outlet_ids_set:
        return
    ditemukan = set(
        (
            await db.execute(
                select(Outlet.id).where(Outlet.id.in_(outlet_ids_set), Outlet.toko_id == toko_id)
            )
        )
        .scalars()
        .all()
    )
    if ditemukan != outlet_ids_set:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Outlet tidak ditemukan")


async def _pastikan_kuota_pengguna(db: AsyncSession, toko_id: uuid.UUID) -> None:
    """`kelola_karyawan` (tahap 3a) TIDAK lagi menggating CRUD pengguna
    dasar - toko Gratis tetap perlu bisa menambah kasir. Yang membatasi
    toko Gratis sekarang adalah kuota jumlah pengguna (`paket.maks_pengguna`),
    bukan fitur on/off. `kelola_karyawan` disisakan utk menggating
    pembuatan role custom & manajemen izin - endpointnya belum ada
    (TODO, lihat docstring modul ini)."""

    paket = await paket_efektif(db, toko_id)
    if paket.maks_pengguna is None:
        return
    jumlah_sekarang = (
        await db.execute(
            select(func.count())
            .select_from(Pengguna)
            .where(Pengguna.toko_id == toko_id, Pengguna.deleted_at.is_(None))
        )
    ).scalar_one()
    if jumlah_sekarang + 1 > paket.maks_pengguna:
        raise HTTPException(
            status.HTTP_403_FORBIDDEN,
            detail={"kode": "kuota_habis", "jenis": "pengguna", "batas": paket.maks_pengguna},
        )


router = APIRouter(tags=["pengguna"])


async def _ke_pengguna_out(db: AsyncSession, pengguna: Pengguna) -> PenggunaOut:
    outlet_ids = (
        await db.execute(select(AksesOutlet.outlet_id).where(AksesOutlet.pengguna_id == pengguna.id))
    ).scalars().all()
    return PenggunaOut(
        id=pengguna.id, toko_id=pengguna.toko_id, role_id=pengguna.role_id, nama=pengguna.nama,
        email=pengguna.email, no_hp=pengguna.no_hp, aktif=pengguna.aktif, outlet_ids=list(outlet_ids),
    )


async def _jumlah_owner_aktif_lain(db: AsyncSession, toko_id: uuid.UUID, kecuali_pengguna_id: uuid.UUID) -> int:
    """Hitung Owner AKTIF selain [kecuali_pengguna_id] - dipakai utk
    menolak nonaktifkan/hapus/ganti-role Owner TERAKHIR (tahap 5 prinsip
    "jangan pernah toko kehilangan Owner sama sekali")."""
    owner_role = (await db.execute(select(Role).where(Role.nama == "Owner", Role.is_system.is_(True)))).scalar_one()
    jumlah = await db.scalar(
        select(func.count()).select_from(Pengguna).where(
            Pengguna.toko_id == toko_id, Pengguna.role_id == owner_role.id,
            Pengguna.aktif.is_(True), Pengguna.deleted_at.is_(None), Pengguna.id != kecuali_pengguna_id,
        )
    )
    return jumlah or 0


async def _apakah_role_owner(db: AsyncSession, role_id: uuid.UUID) -> bool:
    role = await db.get(Role, role_id)
    return role is not None and role.nama == "Owner" and role.is_system


@router.get("/roles", response_model=list[RoleOut])
async def daftar_role(
    toko_id: uuid.UUID = Depends(get_toko_id), db: AsyncSession = Depends(get_db)
) -> list[Role]:
    rows = await db.execute(
        select(Role).where(
            Role.deleted_at.is_(None), or_(Role.is_system.is_(True), Role.toko_id == toko_id)
        )
    )
    return list(rows.scalars().all())


@router.get("/pengguna", response_model=list[PenggunaOut])
async def daftar_pengguna(
    toko_id: uuid.UUID = Depends(get_toko_id), db: AsyncSession = Depends(get_db)
) -> list[PenggunaOut]:
    rows = await db.execute(
        select(Pengguna).where(Pengguna.toko_id == toko_id, Pengguna.deleted_at.is_(None))
    )
    return [await _ke_pengguna_out(db, p) for p in rows.scalars().all()]


@router.post("/pengguna", response_model=PenggunaOut, status_code=status.HTTP_201_CREATED)
async def tambah_pengguna(
    body: PenggunaIn,
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> PenggunaOut:
    if not await has_izin(db, role_id, "pengguna.kelola"):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Role ini tidak punya izin pengguna.kelola")

    await _pastikan_kuota_pengguna(db, toko_id)
    await _pastikan_role_milik_toko(db, body.role_id, toko_id)
    await _pastikan_outlet_ids_milik_toko(db, body.outlet_ids, toko_id)

    pengguna_baru = Pengguna(
        toko_id=toko_id,
        role_id=body.role_id,
        nama=body.nama,
        email=body.email,
        no_hp=body.no_hp,
        pin_hash=hash_password(body.pin) if body.pin else None,
    )
    db.add(pengguna_baru)
    await db.flush()

    for outlet_id in body.outlet_ids:
        db.add(AksesOutlet(pengguna_id=pengguna_baru.id, outlet_id=outlet_id))

    await catat_audit(
        db, toko_id=toko_id, pengguna_id=pengguna_id, aksi="tambah_pengguna",
        tabel="pengguna", record_id=pengguna_baru.id,
        data_baru={"nama": body.nama, "role_id": str(body.role_id)},
    )
    await db.commit()
    await db.refresh(pengguna_baru)
    return await _ke_pengguna_out(db, pengguna_baru)


async def _ambil_pengguna_milik_toko(pengguna_id: uuid.UUID, toko_id: uuid.UUID, db: AsyncSession) -> Pengguna:
    pengguna = await db.get(Pengguna, pengguna_id)
    if pengguna is None or pengguna.toko_id != toko_id or pengguna.deleted_at is not None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Pengguna tidak ditemukan")
    return pengguna


@router.get("/pengguna/{pengguna_id}", response_model=PenggunaOut)
async def detail_pengguna(
    pengguna_id: uuid.UUID,
    toko_id: uuid.UUID = Depends(get_toko_id),
    db: AsyncSession = Depends(get_db),
) -> PenggunaOut:
    pengguna = await _ambil_pengguna_milik_toko(pengguna_id, toko_id, db)
    return await _ke_pengguna_out(db, pengguna)


@router.patch("/pengguna/{pengguna_id}", response_model=PenggunaOut)
async def ubah_pengguna(
    pengguna_id: uuid.UUID,
    body: PenggunaUpdateIn,
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_login_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> PenggunaOut:
    if not await has_izin(db, role_id, "pengguna.kelola"):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Role ini tidak punya izin pengguna.kelola")

    pengguna = await _ambil_pengguna_milik_toko(pengguna_id, toko_id, db)
    updated = body.model_dump(exclude_unset=True)
    outlet_ids = updated.pop("outlet_ids", None)

    # Validasi kepemilikan role_id (404 kalau role_id tidak dikenal/milik
    # toko lain) WAJIB lebih dulu drpd aturan self/last-owner di bawah -
    # aturan2 itu berasumsi role_id-nya valid, jadi role_id palsu harus
    # ditolak sbg 404 "tidak ditemukan", bukan ketimpa 400 "tidak boleh".
    if updated.get("role_id") is not None:
        await _pastikan_role_milik_toko(db, updated["role_id"], toko_id)

    # Tolak menonaktifkan diri sendiri, DAN tolak ganti role diri sendiri
    # keluar dari Owner (dua-duanya bentuk "mengunci diri sendiri keluar"
    # yang sama bahayanya) - pengguna lain yang masih Owner/berizin boleh
    # melakukan dua hal ini ke SIAPA PUN SELAIN diri sendiri.
    if pengguna_id == pengguna_login_id:
        if updated.get("aktif") is False:
            raise HTTPException(status.HTTP_400_BAD_REQUEST, "Tidak bisa menonaktifkan diri sendiri")
        if updated.get("role_id") is not None and not await _apakah_role_owner(db, updated["role_id"]):
            if await _apakah_role_owner(db, pengguna.role_id):
                raise HTTPException(status.HTTP_400_BAD_REQUEST, "Tidak bisa mengganti role diri sendiri keluar dari Owner")

    # Tolak menonaktifkan/mengganti-role Owner TERAKHIR yang masih aktif.
    if await _apakah_role_owner(db, pengguna.role_id):
        akan_lepas_owner = updated.get("aktif") is False or (
            updated.get("role_id") is not None and not await _apakah_role_owner(db, updated["role_id"])
        )
        if akan_lepas_owner and await _jumlah_owner_aktif_lain(db, toko_id, pengguna_id) == 0:
            raise HTTPException(
                status.HTTP_400_BAD_REQUEST,
                "Tidak bisa menonaktifkan/mengganti role Owner terakhir toko ini",
            )

    data_lama = {k: str(getattr(pengguna, k)) for k in updated}
    for field, value in updated.items():
        setattr(pengguna, field, value)

    if outlet_ids is not None:
        await _pastikan_outlet_ids_milik_toko(db, outlet_ids, toko_id)
        await db.execute(delete(AksesOutlet).where(AksesOutlet.pengguna_id == pengguna_id))
        for outlet_id in outlet_ids:
            db.add(AksesOutlet(pengguna_id=pengguna_id, outlet_id=outlet_id))

    await catat_audit(
        db, toko_id=toko_id, pengguna_id=pengguna_login_id, aksi="ubah_pengguna",
        tabel="pengguna", record_id=pengguna.id,
        data_lama=data_lama, data_baru={k: str(v) for k, v in updated.items()},
    )
    await db.commit()
    await db.refresh(pengguna)
    return await _ke_pengguna_out(db, pengguna)


@router.post("/pengguna/{pengguna_id}/reset-pin", status_code=status.HTTP_204_NO_CONTENT)
async def reset_pin_pengguna(
    pengguna_id: uuid.UUID,
    body: ResetPinIn,
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_login_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> None:
    if not await has_izin(db, role_id, "pengguna.kelola"):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Role ini tidak punya izin pengguna.kelola")
    pengguna = await _ambil_pengguna_milik_toko(pengguna_id, toko_id, db)
    pengguna.pin_hash = hash_password(body.pin)
    await catat_audit(
        db, toko_id=toko_id, pengguna_id=pengguna_login_id, aksi="reset_pin_pengguna",
        tabel="pengguna", record_id=pengguna.id, data_baru={"pengguna_target": pengguna.nama},
    )
    await db.commit()


@router.delete("/pengguna/{pengguna_id}", status_code=status.HTTP_204_NO_CONTENT)
async def hapus_pengguna(
    pengguna_id: uuid.UUID,
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_login_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> None:
    if not await has_izin(db, role_id, "pengguna.kelola"):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Role ini tidak punya izin pengguna.kelola")
    pengguna = await _ambil_pengguna_milik_toko(pengguna_id, toko_id, db)

    if pengguna_id == pengguna_login_id:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Tidak bisa menghapus akun sendiri")
    if await _apakah_role_owner(db, pengguna.role_id) and await _jumlah_owner_aktif_lain(db, toko_id, pengguna_id) == 0:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Tidak bisa menghapus Owner terakhir toko ini")

    # Soft delete - transaksi lama (ItemTransaksi/Transaksi.pengguna_id)
    # tetap utuh, cuma tidak bisa login/dipilih lagi.
    pengguna.deleted_at = datetime.now(UTC)
    pengguna.aktif = False
    await catat_audit(
        db, toko_id=toko_id, pengguna_id=pengguna_login_id, aksi="hapus_pengguna",
        tabel="pengguna", record_id=pengguna.id, data_lama={"nama": pengguna.nama},
    )
    await db.commit()
