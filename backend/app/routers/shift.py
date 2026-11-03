import uuid
from datetime import UTC, datetime

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_db
from app.core.deps import get_pengguna_id, get_role_id, get_toko_id, require_outlet_access
from app.models.transaksi import KasShift, Shift
from app.schemas.shift import BukaShiftIn, KasShiftIn, KasShiftOut, ShiftOut, TutupShiftIn
from app.services.kepemilikan import get_outlet_milik_toko
from app.services.shift_service import hitung_kas_seharusnya

router = APIRouter(prefix="/shift", tags=["shift"])


@router.post("/buka", response_model=ShiftOut, status_code=status.HTTP_201_CREATED)
async def buka_shift(
    body: BukaShiftIn,
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> Shift:
    await get_outlet_milik_toko(db, body.outlet_id, toko_id)
    await require_outlet_access(db, pengguna_id=pengguna_id, role_id=role_id, outlet_id=body.outlet_id)

    sudah_buka = await db.scalar(
        select(Shift).where(
            Shift.outlet_id == body.outlet_id, Shift.status == "buka", Shift.deleted_at.is_(None)
        )
    )
    if sudah_buka is not None:
        raise HTTPException(status.HTTP_409_CONFLICT, "Sudah ada shift yang terbuka di outlet ini")

    shift = Shift(
        toko_id=toko_id,
        outlet_id=body.outlet_id,
        pengguna_id=pengguna_id,
        dibuka_pada=datetime.now(UTC),
        modal_awal=body.modal_awal,
        status="buka",
    )
    db.add(shift)
    await db.commit()
    await db.refresh(shift)
    return shift


async def _ambil_shift_milik_toko(shift_id: uuid.UUID, toko_id: uuid.UUID, db: AsyncSession) -> Shift:
    shift = await db.get(Shift, shift_id)
    if shift is None or shift.toko_id != toko_id or shift.deleted_at is not None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Shift tidak ditemukan")
    return shift


@router.post("/{shift_id}/tutup", response_model=ShiftOut)
async def tutup_shift(
    shift_id: uuid.UUID,
    body: TutupShiftIn,
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> Shift:
    shift = await _ambil_shift_milik_toko(shift_id, toko_id, db)
    await require_outlet_access(db, pengguna_id=pengguna_id, role_id=role_id, outlet_id=shift.outlet_id)
    if shift.status != "buka":
        raise HTTPException(status.HTTP_409_CONFLICT, "Shift ini sudah ditutup")

    kas_seharusnya = await hitung_kas_seharusnya(db, shift.id, shift.modal_awal)
    shift.kas_seharusnya = kas_seharusnya
    shift.kas_aktual = body.kas_aktual
    shift.selisih = body.kas_aktual - kas_seharusnya
    shift.status = "tutup"
    shift.ditutup_pada = datetime.now(UTC)
    await db.commit()
    await db.refresh(shift)
    return shift


@router.post("/{shift_id}/kas", response_model=KasShiftOut, status_code=status.HTTP_201_CREATED)
async def catat_kas(
    shift_id: uuid.UUID,
    body: KasShiftIn,
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> KasShift:
    shift = await _ambil_shift_milik_toko(shift_id, toko_id, db)
    await require_outlet_access(db, pengguna_id=pengguna_id, role_id=role_id, outlet_id=shift.outlet_id)
    if shift.status != "buka":
        raise HTTPException(status.HTTP_409_CONFLICT, "Shift ini sudah ditutup")

    kas = KasShift(
        shift_id=shift.id, jenis=body.jenis, jumlah=body.jumlah, keterangan=body.keterangan,
        dibuat_oleh=pengguna_id,
    )
    db.add(kas)
    await db.commit()
    await db.refresh(kas)
    return kas


@router.get("/{shift_id}", response_model=ShiftOut)
async def detail_shift(
    shift_id: uuid.UUID, toko_id: uuid.UUID = Depends(get_toko_id), db: AsyncSession = Depends(get_db)
) -> Shift:
    return await _ambil_shift_milik_toko(shift_id, toko_id, db)
