"""F3.E - "Simpan pesanan" (open bill), endpoint cadangan/backup SAJA.
Lihat docstring pesanan_tersimpan_service.py utk kenapa ini terpisah dari
router transaksi.py (checkout biasa)."""

import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_db
from app.core.deps import get_pengguna_id, get_role_id, get_toko_id
from app.schemas.pesanan_tersimpan import BatalkanPesananIn, PesananTersimpanIn, PesananTersimpanOut
from app.services.izin_service import has_izin
from app.services.pesanan_tersimpan_service import (
    batalkan_pesanan_tersimpan,
    hapus_pesanan_tersimpan,
    simpan_pesanan_cadangan,
)

router = APIRouter(prefix="/transaksi/pesanan-tersimpan", tags=["pesanan-tersimpan"])


@router.post("", response_model=PesananTersimpanOut, status_code=status.HTTP_201_CREATED)
async def simpan(
    body: PesananTersimpanIn,
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> PesananTersimpanOut:
    if not await has_izin(db, role_id, "transaksi.buat"):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Role ini tidak punya izin transaksi.buat")
    hasil = await simpan_pesanan_cadangan(db, toko_id=toko_id, pengguna_id=pengguna_id, body=body)
    return PesananTersimpanOut(id=hasil.id, nomor_struk=hasil.nomor_struk, status=hasil.status, total=hasil.total)


@router.delete("/{pesanan_id}", status_code=status.HTTP_204_NO_CONTENT)
async def hapus(
    pesanan_id: uuid.UUID,
    toko_id: uuid.UUID = Depends(get_toko_id),
    db: AsyncSession = Depends(get_db),
) -> None:
    await hapus_pesanan_tersimpan(db, toko_id=toko_id, pesanan_id=pesanan_id)


@router.post("/{pesanan_id}/batalkan", status_code=status.HTTP_204_NO_CONTENT)
async def batalkan(
    pesanan_id: uuid.UUID,
    body: BatalkanPesananIn,
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    db: AsyncSession = Depends(get_db),
) -> None:
    """Temuan#2 - jalur ONLINE (langsung). Jalur OFFLINE (push) lewat
    kategori `pesanan_batal` di /sync/push, lihat sync_service.py -
    KEDUANYA memanggil batalkan_pesanan_tersimpan yang sama supaya aturan
    approval/audit_log identik, tidak ada jalur belakang yang lebih longgar."""
    await batalkan_pesanan_tersimpan(
        db,
        toko_id=toko_id,
        pengguna_id=pengguna_id,
        pesanan_id=pesanan_id,
        alasan=body.alasan,
        disetujui_oleh=body.disetujui_oleh,
    )
