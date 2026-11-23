import uuid
from decimal import Decimal

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_db
from app.core.deps import get_pengguna_id, get_role_id, get_toko_id, require_outlet_access
from app.models.akun import Pengguna
from app.models.stok import MutasiStok
from app.schemas.stok_mutasi import MutasiStokManualIn, MutasiStokManualOut
from app.services.izin_service import has_izin
from app.services.kepemilikan import get_outlet_milik_toko, pastikan_produk_milik_toko
from app.services.stok_service import catat_mutasi

router = APIRouter(prefix="/stok/mutasi", tags=["stok-mutasi"])


@router.post("", response_model=MutasiStokManualOut, status_code=status.HTTP_201_CREATED)
async def catat_mutasi_manual(
    body: MutasiStokManualIn,
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> MutasiStokManualOut:
    """Menerima mutasi stok yang dicatat tangan di HP (pembelian, opname, penyesuaian, dst) saat sinkron.

    Idempotent menurut `id`: id yang sudah ada tidak diterapkan lagi (HP boleh mengirim ulang setelah
    koneksi putus tanpa menggandakan stok)."""

    if not await has_izin(db, role_id, "stok.kelola"):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Role ini tidak punya izin stok.kelola")
    if body.qty == 0:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "Qty tidak boleh 0")

    await get_outlet_milik_toko(db, body.outlet_id, toko_id)
    await require_outlet_access(db, pengguna_id=pengguna_id, role_id=role_id, outlet_id=body.outlet_id)
    await pastikan_produk_milik_toko(
        db, [body.produk_id], toko_id, varian_ids=[body.varian_id] if body.varian_id else None
    )

    ada = await db.get(MutasiStok, body.id)
    if ada is not None:
        if ada.toko_id != toko_id:
            raise HTTPException(status.HTTP_409_CONFLICT, "Id mutasi sudah dipakai")
        return MutasiStokManualOut(
            id=ada.id, saldo_setelah=Decimal(str(ada.saldo_setelah)) if ada.saldo_setelah is not None else None,
            diterapkan=False,
        )

    pencatat = pengguna_id
    if body.pengguna_id is not None and body.pengguna_id != pengguna_id:
        karyawan = await db.get(Pengguna, body.pengguna_id)
        if karyawan is not None and karyawan.toko_id == toko_id and karyawan.deleted_at is None:
            pencatat = karyawan.id

    await catat_mutasi(
        db,
        toko_id=toko_id,
        outlet_id=body.outlet_id,
        produk_id=body.produk_id,
        varian_id=body.varian_id,
        jenis=body.jenis,
        qty=body.qty,
        ref_tipe="manual",
        catatan=body.catatan,
        dibuat_oleh=pencatat,
        mutasi_id=body.id,
    )
    await db.commit()
    baru = await db.get(MutasiStok, body.id)
    return MutasiStokManualOut(
        id=body.id,
        saldo_setelah=Decimal(str(baru.saldo_setelah)) if baru is not None and baru.saldo_setelah is not None else None,
        diterapkan=True,
    )
