import uuid
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_db
from app.core.deps import get_pengguna_id, get_role_id, get_toko_id, require_outlet_access
from app.models.transaksi import Shift
from app.schemas.laporan import (
    LabaRugiOut,
    LaporanPiutangOut,
    LaporanShiftOut,
    ProdukTerlarisOut,
    RingkasanPenjualanOut,
)
from app.services.fitur_service import require_fitur
from app.services.izin_service import has_izin
from app.services import laba_rugi_service, laporan_service
from app.services.kepemilikan import get_outlet_milik_toko

router = APIRouter(prefix="/laporan", tags=["laporan"])


@router.get("/penjualan", response_model=RingkasanPenjualanOut)
async def laporan_penjualan(
    dari: datetime = Query(...),
    sampai: datetime = Query(...),
    outlet_id: uuid.UUID | None = Query(None),
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> RingkasanPenjualanOut:
    # outlet_id (kalau diisi) tetap WAJIB divalidasi milik toko ini -
    # tanpa ini query di laporan_service akan AND-kan toko_id+outlet_id
    # jadi tidak bocor data, tapi lebih konsisten & jelas (404, bukan
    # diam-diam kembalikan laporan kosong) kalau outlet_id itu dari toko
    # lain / tidak ada sama sekali.
    if outlet_id is not None:
        await get_outlet_milik_toko(db, outlet_id, toko_id)
        await require_outlet_access(db, pengguna_id=pengguna_id, role_id=role_id, outlet_id=outlet_id)
    await laporan_service.pastikan_rentang_diizinkan(db, toko_id=toko_id, dari=dari, sampai=sampai)
    return await laporan_service.ringkasan_penjualan(
        db, toko_id=toko_id, outlet_id=outlet_id, dari=dari, sampai=sampai
    )


@router.get("/produk-terlaris", response_model=list[ProdukTerlarisOut])
async def laporan_produk_terlaris(
    dari: datetime = Query(...),
    sampai: datetime = Query(...),
    outlet_id: uuid.UUID | None = Query(None),
    limit: int = Query(5, ge=1, le=50),
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> list[ProdukTerlarisOut]:
    if outlet_id is not None:
        await get_outlet_milik_toko(db, outlet_id, toko_id)
        await require_outlet_access(db, pengguna_id=pengguna_id, role_id=role_id, outlet_id=outlet_id)
    await laporan_service.pastikan_rentang_diizinkan(db, toko_id=toko_id, dari=dari, sampai=sampai)
    return await laporan_service.produk_terlaris(
        db, toko_id=toko_id, outlet_id=outlet_id, dari=dari, sampai=sampai, limit=limit
    )


@router.get("/piutang", response_model=LaporanPiutangOut)
async def laporan_piutang(
    outlet_id: uuid.UUID | None = Query(None),
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> LaporanPiutangOut:
    if outlet_id is not None:
        await get_outlet_milik_toko(db, outlet_id, toko_id)
        await require_outlet_access(db, pengguna_id=pengguna_id, role_id=role_id, outlet_id=outlet_id)
    return await laporan_service.piutang(db, toko_id=toko_id, outlet_id=outlet_id)


@router.get("/shift/{shift_id}", response_model=LaporanShiftOut)
async def laporan_per_shift(
    shift_id: uuid.UUID,
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> LaporanShiftOut:
    shift = await db.get(Shift, shift_id)
    if shift is None or shift.toko_id != toko_id or shift.deleted_at is not None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Shift tidak ditemukan")
    await require_outlet_access(db, pengguna_id=pengguna_id, role_id=role_id, outlet_id=shift.outlet_id)
    return await laporan_service.laporan_shift(db, toko_id=toko_id, shift=shift)


@router.get(
    "/laba-rugi", response_model=LabaRugiOut, dependencies=[Depends(require_fitur("profit_loss"))]
)
async def laporan_laba_rugi(
    dari: datetime = Query(...),
    sampai: datetime = Query(...),
    outlet_id: uuid.UUID | None = Query(None),
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> LabaRugiOut:
    # Laba rugi memuat HPP dan biaya: hanya peran dengan izin lihat laporan (Owner/Manajer).
    if not await has_izin(db, role_id, "laporan.lihat"):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Tidak punya izin melihat laporan laba rugi")
    if sampai <= dari:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Rentang waktu tidak valid")
    if outlet_id is not None:
        await get_outlet_milik_toko(db, outlet_id, toko_id)
        await require_outlet_access(db, pengguna_id=pengguna_id, role_id=role_id, outlet_id=outlet_id)
    await laporan_service.pastikan_rentang_diizinkan(db, toko_id=toko_id, dari=dari, sampai=sampai)
    return await laba_rugi_service.laba_rugi(db, toko_id=toko_id, outlet_id=outlet_id, dari=dari, sampai=sampai)
