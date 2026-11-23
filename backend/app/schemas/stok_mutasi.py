import uuid
from decimal import Decimal
from typing import Literal

from pydantic import BaseModel, Field

# Jenis yang boleh dicatat tangan dari aplikasi. Penjualan/refund/void sengaja tidak ada: ketiganya hanya
# lahir dari transaksi di server (checkout/refund/void) dan tidak boleh dibuat lewat pencatatan manual.
JenisMutasiManual = Literal[
    "stok_awal", "pembelian", "opname", "transfer_masuk", "transfer_keluar", "penyesuaian", "produksi"
]


class MutasiStokManualIn(BaseModel):
    id: uuid.UUID  # id dari HP; dipakai agar pengiriman ulang tidak menerapkan mutasi dua kali
    outlet_id: uuid.UUID
    produk_id: uuid.UUID
    varian_id: uuid.UUID | None = None
    jenis: JenisMutasiManual
    qty: Decimal = Field(description="Positif menambah saldo, negatif mengurangi")
    catatan: str | None = None
    # Karyawan yang benar-benar mencatat di HP. Satu token perangkat dipakai bergilir, jadi tanpa ini semua mutasi
    # tercatat atas nama pemilik token. Diabaikan (kembali ke pemilik token) bila bukan karyawan toko ini.
    pengguna_id: uuid.UUID | None = None


class MutasiStokManualOut(BaseModel):
    id: uuid.UUID
    saldo_setelah: Decimal | None
    diterapkan: bool  # false = id ini sudah pernah diterima, tidak diterapkan lagi
