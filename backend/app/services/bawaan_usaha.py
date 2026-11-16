"""Data bawaan toko baru menurut jenis usaha (dokumen IMOGI).

Dipanggil saat pendaftaran toko (routers/auth.py). Tipe pesanan dibuat di
server supaya ikut sync pull dan HP tidak bergantung pada bawaan lokalnya.
Biaya layanan (service charge) 5% bawaan HANYA untuk jenis usaha yang makan di
tempat (Kafe dan Restoran) dan hanya ditautkan ke tipe "Makan di tempat"
(IMOGI no. 6: biaya layanan per tipe pesanan)."""

import uuid

from sqlalchemy.ext.asyncio import AsyncSession

from app.models.outlet import PengaturanOutlet
from app.models.order import TipeOrder, TipeOrderPajak
from app.models.promo import Pajak

# Jenis usaha F&B yang melayani makan di tempat dan memungut biaya layanan bawaan.
JENIS_USAHA_SERVICE_BAWAAN = frozenset({"CAF", "RES"})
SERVICE_BAWAAN_PERSEN = 5


# Panduan IMOGI: pajak (PB1) ditambahkan di atas harga untuk jenis usaha ini. Bahan segar/beku (FRZ)
# tidak dikenai bawaan karena lebih mirip ritel bahan baku.
JENIS_USAHA_PB1_BAWAAN = frozenset({"CAF", "RES", "CAT", "BRD", "BEV", "STL"})
PB1_BAWAAN_PERSEN = 10
FOOTER_STRUK_BAWAAN = "Terima kasih, selamat menikmati!"


async def seed_pengaturan_bawaan(
    db: AsyncSession, *, toko_id: uuid.UUID, outlet_id: uuid.UUID, jenis_usaha: str | None
) -> None:
    """Nilai awal pengaturan toko baru menurut jenis usaha. Hanya nilai yang TIDAK terkunci paket
    (pesan penutup struk, pajak PB1); struk ringkas dan nomor antrean tetap mengikuti paket."""
    kode = (jenis_usaha or "").upper()
    db.add(PengaturanOutlet(outlet_id=outlet_id, footer_struk=FOOTER_STRUK_BAWAAN))
    if kode in JENIS_USAHA_PB1_BAWAAN:
        db.add(
            Pajak(
                toko_id=toko_id, nama="PB1", tipe="pajak", persen=PB1_BAWAAN_PERSEN, termasuk_harga=False, urutan=1, aktif=True
            )
        )
    await db.flush()


async def seed_tipe_order_dan_service(db: AsyncSession, *, toko_id: uuid.UUID, jenis_usaha: str | None) -> None:
    makan = TipeOrder(toko_id=toko_id, nama="Makan di tempat", kanal="makan_di_tempat", pakai_meja=True, urutan=0)
    db.add_all(
        [
            makan,
            TipeOrder(toko_id=toko_id, nama="Bawa pulang", kanal="bawa_pulang", urutan=1),
            TipeOrder(toko_id=toko_id, nama="Delivery", kanal="antar", urutan=2),
        ]
    )
    await db.flush()

    if (jenis_usaha or "").upper() in JENIS_USAHA_SERVICE_BAWAAN:
        service = Pajak(
            toko_id=toko_id,
            nama="Service Charge",
            tipe="service",
            persen=SERVICE_BAWAAN_PERSEN,
            termasuk_harga=False,
            urutan=0,
            aktif=True,
        )
        db.add(service)
        await db.flush()
        db.add(TipeOrderPajak(tipe_order_id=makan.id, pajak_id=service.id))
        await db.flush()
