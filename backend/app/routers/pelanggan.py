"""Modul 6 - pelanggan + level_member/aturan_poin (loyalty, modul 10).
Digabung satu file krn level_member/aturan_poin murni pengaturan
pendukung pelanggan (tahap 5 B.7), bukan domain terpisah."""

import uuid
from datetime import UTC, datetime

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_db
from app.core.deps import get_pengguna_id, get_role_id, get_toko_id
from app.models.pelanggan import AturanPoin, LevelMember, Pelanggan, RiwayatPoin
from app.schemas.pelanggan import (
    AturanPoinIn,
    AturanPoinOut,
    AturanPoinUpdateIn,
    LevelMemberIn,
    LevelMemberOut,
    LevelMemberUpdateIn,
    PelangganIn,
    PelangganOut,
    PelangganUpdateIn,
    RiwayatPoinOut,
)
from app.services.audit_service import catat_audit
from app.services.fitur_service import require_fitur
from app.services.izin_service import has_izin

router = APIRouter(tags=["pelanggan"])


async def _wajib_izin_pelanggan_kelola(db: AsyncSession, role_id: uuid.UUID) -> None:
    if not await has_izin(db, role_id, "pelanggan.kelola"):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Role ini tidak punya izin pelanggan.kelola")


@router.get("/pelanggan", response_model=list[PelangganOut])
async def daftar_pelanggan(
    toko_id: uuid.UUID = Depends(get_toko_id), db: AsyncSession = Depends(get_db)
) -> list[Pelanggan]:
    rows = await db.execute(
        select(Pelanggan).where(Pelanggan.toko_id == toko_id, Pelanggan.deleted_at.is_(None))
    )
    return list(rows.scalars().all())


async def _pastikan_level_member_milik_toko(
    db: AsyncSession, level_member_id: uuid.UUID | None, toko_id: uuid.UUID
) -> None:
    if level_member_id is None:
        return
    level = await db.get(LevelMember, level_member_id)
    if level is None or level.toko_id != toko_id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Level member tidak ditemukan")


@router.post("/pelanggan", response_model=PelangganOut, status_code=status.HTTP_201_CREATED)
async def tambah_pelanggan(
    body: PelangganIn,
    toko_id: uuid.UUID = Depends(get_toko_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> Pelanggan:
    await _wajib_izin_pelanggan_kelola(db, role_id)
    await _pastikan_level_member_milik_toko(db, body.level_member_id, toko_id)
    pelanggan = Pelanggan(toko_id=toko_id, **body.model_dump())
    db.add(pelanggan)
    await db.commit()
    await db.refresh(pelanggan)
    return pelanggan


async def _ambil_pelanggan_milik_toko(db: AsyncSession, pelanggan_id: uuid.UUID, toko_id: uuid.UUID) -> Pelanggan:
    pelanggan = await db.get(Pelanggan, pelanggan_id)
    if pelanggan is None or pelanggan.toko_id != toko_id or pelanggan.deleted_at is not None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Pelanggan tidak ditemukan")
    return pelanggan


@router.get("/pelanggan/{pelanggan_id}", response_model=PelangganOut)
async def detail_pelanggan(
    pelanggan_id: uuid.UUID,
    toko_id: uuid.UUID = Depends(get_toko_id),
    db: AsyncSession = Depends(get_db),
) -> Pelanggan:
    return await _ambil_pelanggan_milik_toko(db, pelanggan_id, toko_id)


@router.patch("/pelanggan/{pelanggan_id}", response_model=PelangganOut)
async def ubah_pelanggan(
    pelanggan_id: uuid.UUID,
    body: PelangganUpdateIn,
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> Pelanggan:
    await _wajib_izin_pelanggan_kelola(db, role_id)
    pelanggan = await _ambil_pelanggan_milik_toko(db, pelanggan_id, toko_id)

    perubahan = body.model_dump(exclude_unset=True)
    if "level_member_id" in perubahan:
        await _pastikan_level_member_milik_toko(db, perubahan["level_member_id"], toko_id)

    data_lama = {k: str(getattr(pelanggan, k)) for k in perubahan}
    for field, value in perubahan.items():
        setattr(pelanggan, field, value)
    await catat_audit(
        db, toko_id=toko_id, pengguna_id=pengguna_id, aksi="ubah_pelanggan",
        tabel="pelanggan", record_id=pelanggan.id,
        data_lama=data_lama, data_baru={k: str(v) for k, v in perubahan.items()},
    )
    await db.commit()
    await db.refresh(pelanggan)
    return pelanggan


@router.delete("/pelanggan/{pelanggan_id}", status_code=status.HTTP_204_NO_CONTENT)
async def hapus_pelanggan(
    pelanggan_id: uuid.UUID,
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> None:
    await _wajib_izin_pelanggan_kelola(db, role_id)
    pelanggan = await _ambil_pelanggan_milik_toko(db, pelanggan_id, toko_id)
    # Soft delete - transaksi lama tetap utuh (snapshot nama di item_transaksi
    # / nomor_struk, tidak pernah JOIN balik ke Pelanggan utk tampil struk lama).
    pelanggan.deleted_at = datetime.now(UTC)
    await catat_audit(
        db, toko_id=toko_id, pengguna_id=pengguna_id, aksi="hapus_pelanggan",
        tabel="pelanggan", record_id=pelanggan.id, data_lama={"nama": pelanggan.nama},
    )
    await db.commit()


@router.get("/pelanggan/{pelanggan_id}/riwayat-poin", response_model=list[RiwayatPoinOut])
async def riwayat_poin_pelanggan(
    pelanggan_id: uuid.UUID,
    toko_id: uuid.UUID = Depends(get_toko_id),
    db: AsyncSession = Depends(get_db),
) -> list[RiwayatPoin]:
    await _ambil_pelanggan_milik_toko(db, pelanggan_id, toko_id)
    rows = await db.execute(
        select(RiwayatPoin)
        .where(RiwayatPoin.pelanggan_id == pelanggan_id)
        .order_by(RiwayatPoin.created_at.desc())
    )
    return list(rows.scalars().all())


# ---------------------------------------------------------------------------
# Level member (tahap 5 B.7) - gate fitur 'diskon_member'.
# ---------------------------------------------------------------------------


@router.get("/level-member", response_model=list[LevelMemberOut], dependencies=[Depends(require_fitur("diskon_member"))])
async def daftar_level_member(
    toko_id: uuid.UUID = Depends(get_toko_id), db: AsyncSession = Depends(get_db)
) -> list[LevelMember]:
    rows = await db.execute(select(LevelMember).where(LevelMember.toko_id == toko_id).order_by(LevelMember.urutan))
    return list(rows.scalars().all())


@router.post(
    "/level-member", response_model=LevelMemberOut, status_code=status.HTTP_201_CREATED,
    dependencies=[Depends(require_fitur("diskon_member"))],
)
async def tambah_level_member(
    body: LevelMemberIn,
    toko_id: uuid.UUID = Depends(get_toko_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> LevelMember:
    await _wajib_izin_pelanggan_kelola(db, role_id)
    level = LevelMember(toko_id=toko_id, **body.model_dump())
    db.add(level)
    await db.commit()
    await db.refresh(level)
    return level


async def _ambil_level_member_milik_toko(db: AsyncSession, level_id: uuid.UUID, toko_id: uuid.UUID) -> LevelMember:
    level = await db.get(LevelMember, level_id)
    if level is None or level.toko_id != toko_id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Level member tidak ditemukan")
    return level


@router.patch(
    "/level-member/{level_id}", response_model=LevelMemberOut,
    dependencies=[Depends(require_fitur("diskon_member"))],
)
async def ubah_level_member(
    level_id: uuid.UUID,
    body: LevelMemberUpdateIn,
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> LevelMember:
    await _wajib_izin_pelanggan_kelola(db, role_id)
    level = await _ambil_level_member_milik_toko(db, level_id, toko_id)
    perubahan = body.model_dump(exclude_unset=True)
    data_lama = {k: str(getattr(level, k)) for k in perubahan}
    for field, value in perubahan.items():
        setattr(level, field, value)
    await catat_audit(
        db, toko_id=toko_id, pengguna_id=pengguna_id, aksi="ubah_level_member",
        tabel="level_member", record_id=level.id,
        data_lama=data_lama, data_baru={k: str(v) for k, v in perubahan.items()},
    )
    await db.commit()
    await db.refresh(level)
    return level


@router.delete(
    "/level-member/{level_id}", status_code=status.HTTP_204_NO_CONTENT,
    dependencies=[Depends(require_fitur("diskon_member"))],
)
async def hapus_level_member(
    level_id: uuid.UUID,
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> None:
    """Level member TIDAK punya deleted_at (lihat model) - hapus beneran,
    tapi pelanggan yang masih menautkan `level_member_id` ke baris ini
    WAJIB dilepas dulu (set NULL), supaya tidak jadi FK dangling dan
    tetap konsisten dgn data historis poin (riwayat_poin tidak menyimpan
    level, jadi tidak terdampak)."""
    await _wajib_izin_pelanggan_kelola(db, role_id)
    level = await _ambil_level_member_milik_toko(db, level_id, toko_id)
    terpakai = (
        await db.execute(select(Pelanggan).where(Pelanggan.level_member_id == level_id))
    ).scalars().all()
    for pelanggan in terpakai:
        pelanggan.level_member_id = None
    await catat_audit(
        db, toko_id=toko_id, pengguna_id=pengguna_id, aksi="hapus_level_member",
        tabel="level_member", record_id=level.id, data_lama={"nama": level.nama},
    )
    await db.delete(level)
    await db.commit()


# ---------------------------------------------------------------------------
# Aturan poin (tahap 5 B.7) - satu baris per toko (toko_id = PK), gate fitur
# 'poin_loyalitas'.
# ---------------------------------------------------------------------------


@router.get("/aturan-poin", response_model=AturanPoinOut | None, dependencies=[Depends(require_fitur("poin_loyalitas"))])
async def ambil_aturan_poin(
    toko_id: uuid.UUID = Depends(get_toko_id), db: AsyncSession = Depends(get_db)
) -> AturanPoin | None:
    return await db.get(AturanPoin, toko_id)


@router.put(
    "/aturan-poin", response_model=AturanPoinOut, dependencies=[Depends(require_fitur("poin_loyalitas"))],
)
async def atur_aturan_poin(
    body: AturanPoinIn,
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> AturanPoin:
    """Upsert - satu toko cuma punya satu baris aturan_poin (toko_id = PK)."""
    await _wajib_izin_pelanggan_kelola(db, role_id)
    aturan = await db.get(AturanPoin, toko_id)
    if aturan is None:
        aturan = AturanPoin(toko_id=toko_id, **body.model_dump())
        db.add(aturan)
        data_lama = None
    else:
        data_lama = {
            "nominal_per_poin": str(aturan.nominal_per_poin), "nilai_tukar_poin": str(aturan.nilai_tukar_poin),
            "min_tukar_poin": aturan.min_tukar_poin, "kedaluwarsa_hari": aturan.kedaluwarsa_hari,
            "aktif": aturan.aktif,
        }
        for field, value in body.model_dump().items():
            setattr(aturan, field, value)
    await catat_audit(
        db, toko_id=toko_id, pengguna_id=pengguna_id, aksi="atur_aturan_poin",
        tabel="aturan_poin", record_id=None,
        data_lama=data_lama, data_baru=body.model_dump(mode="json"),
    )
    await db.commit()
    await db.refresh(aturan)
    return aturan


@router.patch(
    "/aturan-poin", response_model=AturanPoinOut, dependencies=[Depends(require_fitur("poin_loyalitas"))],
)
async def ubah_aturan_poin(
    body: AturanPoinUpdateIn,
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> AturanPoin:
    await _wajib_izin_pelanggan_kelola(db, role_id)
    aturan = await db.get(AturanPoin, toko_id)
    if aturan is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Aturan poin belum diatur - pakai PUT utk membuat")

    perubahan = body.model_dump(exclude_unset=True)
    data_lama = {k: str(getattr(aturan, k)) for k in perubahan}
    for field, value in perubahan.items():
        setattr(aturan, field, value)
    await catat_audit(
        db, toko_id=toko_id, pengguna_id=pengguna_id, aksi="ubah_aturan_poin",
        tabel="aturan_poin", record_id=None,
        data_lama=data_lama, data_baru={k: str(v) for k, v in perubahan.items()},
    )
    await db.commit()
    await db.refresh(aturan)
    return aturan
