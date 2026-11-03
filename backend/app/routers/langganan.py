"""F3.F - Paket langganan: lihat paket aktif+pemakaian kuota, bandingkan
fitur antar paket, ajukan minat upgrade (jalur manual LAMA) atau checkout
pembayaran Xendit langsung (jalur BARU - paket aktif otomatis begitu
lunas, lihat services/xendit_service.py)."""

import uuid

from fastapi import APIRouter, Depends, HTTPException, status as http_status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_db
from app.core.deps import get_toko_id
from app.models.outlet import PermintaanUpgrade, Toko
from app.schemas.langganan import (
    CheckoutUpgradeOut,
    LanggananSayaOut,
    PaketOut,
    PermintaanUpgradeIn,
    PermintaanUpgradeOut,
    QrisCheckoutOut,
    StatusCheckoutOut,
    VaCheckoutIn,
    VaCheckoutOut,
)
from app.services.langganan_service import buat_permintaan_upgrade, daftar_paket, langganan_saya
from app.services.xendit_service import (
    buat_checkout_upgrade,
    buat_qris,
    buat_va,
    cek_status_dan_aktivasi,
    simulasikan_bayar,
)

router = APIRouter(tags=["langganan"])


@router.get("/paket", response_model=list[PaketOut])
async def semua_paket(db: AsyncSession = Depends(get_db)) -> list[PaketOut]:
    return await daftar_paket(db)


@router.get("/langganan/saya", response_model=LanggananSayaOut)
async def saya(
    toko_id: uuid.UUID = Depends(get_toko_id), db: AsyncSession = Depends(get_db)
) -> LanggananSayaOut:
    return await langganan_saya(db, toko_id)


@router.post(
    "/langganan/permintaan-upgrade", response_model=PermintaanUpgradeOut, status_code=201
)
async def ajukan_upgrade(
    body: PermintaanUpgradeIn,
    toko_id: uuid.UUID = Depends(get_toko_id),
    db: AsyncSession = Depends(get_db),
) -> PermintaanUpgradeOut:
    hasil = await buat_permintaan_upgrade(db, toko_id=toko_id, body=body)
    return PermintaanUpgradeOut.model_validate(hasil)


@router.post(
    "/langganan/checkout-upgrade", response_model=CheckoutUpgradeOut, status_code=201
)
async def checkout_upgrade(
    body: PermintaanUpgradeIn,
    toko_id: uuid.UUID = Depends(get_toko_id),
    db: AsyncSession = Depends(get_db),
) -> CheckoutUpgradeOut:
    toko = await db.get(Toko, toko_id)
    hasil = await buat_checkout_upgrade(
        db, toko_id=toko_id, body=body, email_pembayar=toko.email if toko else None
    )
    return CheckoutUpgradeOut(
        id=hasil.id,
        invoice_url=hasil.invoice_url,
        jumlah_bayar=hasil.jumlah_bayar,
        status=hasil.status,
    )


@router.get("/langganan/checkout-upgrade/{permintaan_id}/status", response_model=StatusCheckoutOut)
async def status_checkout_upgrade(
    permintaan_id: uuid.UUID,
    toko_id: uuid.UUID = Depends(get_toko_id),
    db: AsyncSession = Depends(get_db),
) -> StatusCheckoutOut:
    """App manggil ini begitu user kembali dari halaman bayar Xendit -
    lihat catatan "jalur polling" di xendit_service.py kenapa ini perlu
    ADA SENDIRI, bukan cuma andalkan webhook."""
    permintaan = await db.get(PermintaanUpgrade, permintaan_id)
    if permintaan is None or permintaan.toko_id != toko_id:
        raise HTTPException(http_status.HTTP_404_NOT_FOUND, "Permintaan tidak ditemukan")
    status_terbaru = await cek_status_dan_aktivasi(db, permintaan)
    return StatusCheckoutOut(status=status_terbaru)


@router.post("/langganan/checkout-upgrade/qris", response_model=QrisCheckoutOut, status_code=201)
async def checkout_upgrade_qris(
    body: PermintaanUpgradeIn,
    toko_id: uuid.UUID = Depends(get_toko_id),
    db: AsyncSession = Depends(get_db),
) -> QrisCheckoutOut:
    """Jalur BARU - QR dirender LANGSUNG di app (tanpa redirect browser),
    lihat xendit_service.buat_qris."""
    permintaan, qr_string = await buat_qris(db, toko_id=toko_id, body=body)
    return QrisCheckoutOut(
        id=permintaan.id,
        qr_string=qr_string,
        jumlah_bayar=permintaan.jumlah_bayar,
        status=permintaan.status,
    )


@router.post("/langganan/checkout-upgrade/va", response_model=VaCheckoutOut, status_code=201)
async def checkout_upgrade_va(
    body: VaCheckoutIn,
    toko_id: uuid.UUID = Depends(get_toko_id),
    db: AsyncSession = Depends(get_db),
) -> VaCheckoutOut:
    """Jalur BARU - nomor VA ditampilkan LANGSUNG di app, lihat
    xendit_service.buat_va + BANK_VA_DIDUKUNG utk daftar bank_code valid."""
    permintaan, nomor_va = await buat_va(db, toko_id=toko_id, body=body, bank_code=body.bank_code)
    return VaCheckoutOut(
        id=permintaan.id,
        bank_code=body.bank_code,
        nomor_va=nomor_va,
        jumlah_bayar=permintaan.jumlah_bayar,
        status=permintaan.status,
    )


@router.post("/langganan/checkout-upgrade/{permintaan_id}/simulasi", response_model=StatusCheckoutOut)
async def checkout_upgrade_simulasi(
    permintaan_id: uuid.UUID,
    toko_id: uuid.UUID = Depends(get_toko_id),
    db: AsyncSession = Depends(get_db),
) -> StatusCheckoutOut:
    """KHUSUS SANDBOX - QR/VA Xendit test mode tidak bisa benar2 dibayar,
    endpoint ini memicu Xendit men-simulasikan pembayaran lunas (lihat
    xendit_service.simulasikan_bayar). Di akun Xendit LIVE, Xendit sendiri
    yang akan menolak panggilan /simulate ini (jaring pengaman alami)."""
    permintaan = await db.get(PermintaanUpgrade, permintaan_id)
    if permintaan is None or permintaan.toko_id != toko_id:
        raise HTTPException(http_status.HTTP_404_NOT_FOUND, "Permintaan tidak ditemukan")
    await simulasikan_bayar(db, permintaan)
    status_terbaru = await cek_status_dan_aktivasi(db, permintaan)
    return StatusCheckoutOut(status=status_terbaru)
