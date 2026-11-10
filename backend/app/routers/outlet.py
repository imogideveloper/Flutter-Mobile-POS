import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_db
from app.core.deps import get_role_id, get_toko_id
from app.models.outlet import Outlet, PengaturanOutlet
from app.schemas.outlet import (
    OutletIn,
    OutletOut,
    OutletUpdateIn,
    PengaturanOutletIn,
    PengaturanOutletOut,
)
from app.services.fitur_service import has_fitur, tolak_fitur_terkunci
from app.services.izin_service import has_izin
from app.services.outlet_service import pastikan_kuota_outlet

router = APIRouter(prefix="/outlets", tags=["outlet"])


@router.get("", response_model=list[OutletOut])
async def daftar_outlet(
    toko_id: uuid.UUID = Depends(get_toko_id), db: AsyncSession = Depends(get_db)
) -> list[Outlet]:
    rows = await db.execute(
        select(Outlet).where(Outlet.toko_id == toko_id, Outlet.deleted_at.is_(None))
    )
    return list(rows.scalars().all())


@router.post("", response_model=OutletOut, status_code=status.HTTP_201_CREATED)
async def tambah_outlet(
    body: OutletIn, toko_id: uuid.UUID = Depends(get_toko_id), db: AsyncSession = Depends(get_db)
) -> Outlet:
    jumlah_sekarang = await db.scalar(
        select(func.count()).select_from(Outlet).where(Outlet.toko_id == toko_id, Outlet.deleted_at.is_(None))
    )
    # Outlet PERTAMA toko selalu boleh tanpa fitur `multi_outlet` - setiap
    # toko (termasuk paket Gratis) wajib bisa punya minimal 1 outlet dari
    # awal. Fitur ini baru relevan utk outlet KE-2 dan seterusnya.
    if jumlah_sekarang >= 1 and not await has_fitur(db, toko_id, "multi_outlet"):
        await tolak_fitur_terkunci(db, "multi_outlet")

    await pastikan_kuota_outlet(db, toko_id=toko_id, jumlah_sekarang=jumlah_sekarang)

    outlet = Outlet(toko_id=toko_id, **body.model_dump())
    db.add(outlet)
    await db.commit()
    await db.refresh(outlet)
    return outlet


async def _ambil_outlet_milik_toko(
    outlet_id: uuid.UUID, toko_id: uuid.UUID, db: AsyncSession
) -> Outlet:
    outlet = await db.get(Outlet, outlet_id)
    # toko_id WAJIB dari token (get_toko_id), bukan dari path - baris di
    # bawah ini yang mencegah toko A mengambil/mengubah outlet toko B hanya
    # dengan menebak UUID-nya di URL.
    if outlet is None or outlet.toko_id != toko_id or outlet.deleted_at is not None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Outlet tidak ditemukan")
    return outlet


@router.get("/{outlet_id}", response_model=OutletOut)
async def detail_outlet(
    outlet_id: uuid.UUID,
    toko_id: uuid.UUID = Depends(get_toko_id),
    db: AsyncSession = Depends(get_db),
) -> Outlet:
    return await _ambil_outlet_milik_toko(outlet_id, toko_id, db)


@router.patch("/{outlet_id}", response_model=OutletOut)
async def ubah_outlet(
    outlet_id: uuid.UUID,
    body: OutletUpdateIn,
    toko_id: uuid.UUID = Depends(get_toko_id),
    db: AsyncSession = Depends(get_db),
) -> Outlet:
    outlet = await _ambil_outlet_milik_toko(outlet_id, toko_id, db)
    for field, value in body.model_dump(exclude_unset=True).items():
        setattr(outlet, field, value)
    await db.commit()
    await db.refresh(outlet)
    return outlet


async def _ambil_atau_buat_pengaturan(outlet: Outlet, db: AsyncSession) -> PengaturanOutlet:
    pengaturan = await db.get(PengaturanOutlet, outlet.id)
    if pengaturan is None:
        pengaturan = PengaturanOutlet(outlet_id=outlet.id)
        db.add(pengaturan)
        await db.commit()
        await db.refresh(pengaturan)
    return pengaturan


def _pastikan_izin_pengaturan(has: bool) -> None:
    if not has:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Role ini tidak punya izin pengaturan.kelola")


@router.get("/{outlet_id}/pengaturan", response_model=PengaturanOutletOut)
async def ambil_pengaturan_outlet(
    outlet_id: uuid.UUID,
    toko_id: uuid.UUID = Depends(get_toko_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> PengaturanOutlet:
    _pastikan_izin_pengaturan(await has_izin(db, role_id, "pengaturan.kelola"))
    outlet = await _ambil_outlet_milik_toko(outlet_id, toko_id, db)
    return await _ambil_atau_buat_pengaturan(outlet, db)


@router.patch("/{outlet_id}/pengaturan", response_model=PengaturanOutletOut)
async def ubah_pengaturan_outlet(
    outlet_id: uuid.UUID,
    body: PengaturanOutletIn,
    toko_id: uuid.UUID = Depends(get_toko_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> PengaturanOutlet:
    _pastikan_izin_pengaturan(await has_izin(db, role_id, "pengaturan.kelola"))
    outlet = await _ambil_outlet_milik_toko(outlet_id, toko_id, db)
    pengaturan = await _ambil_atau_buat_pengaturan(outlet, db)

    perubahan = body.model_dump(exclude_unset=True)
    if "lebar_kertas_mm" in perubahan and perubahan["lebar_kertas_mm"] not in (58, 80):
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "lebar_kertas_mm harus 58 atau 80")

    # Tiap field di bawah digate fitur bernama sama - HANYA saat dipakai
    # mengubah nilainya jadi True (aturan tahap 4 bagian B.1). Toko tanpa
    # fitur itu tetap boleh PATCH field lain, atau mematikannya (False).
    for field, kode_fitur in (
        ("struk_ringkas", "struk_ringkas"),
        ("tampil_logo", "logo_struk"),
        ("pakai_nomor_antrean", "nomor_antrean"),
    ):
        # Hanya saat nilainya BENAR-BENAR berubah menjadi True. Klien mengirim ulang seluruh
        # pengaturan tiap simpan, dan tampil_logo bernilai True secara bawaan: tanpa syarat
        # ini toko paket Gratis tidak bisa menyimpan pengaturan lain apa pun (BUG-012).
        if (
            perubahan.get(field) is True
            and getattr(pengaturan, field) is not True
            and not await has_fitur(db, toko_id, kode_fitur)
        ):
            await tolak_fitur_terkunci(db, kode_fitur)

    for field, value in perubahan.items():
        setattr(pengaturan, field, value)
    await db.commit()
    await db.refresh(pengaturan)
    return pengaturan
