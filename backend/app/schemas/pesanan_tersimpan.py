"""F3.E - "Simpan pesanan" (open bill). Versi pertama SENGAJA per-HP
(lihat docs KPI-nya di aturan_harga.md kalau ada, atau catatan di
pesanan_tersimpan_service.py) - endpoint di sini CUMA cadangan/backup
tampilan, BUKAN sumber kebenaran yang bisa dilanjutkan dari HP lain.
Harga/subtotal dipercaya APA ADANYA dari body (beda dgn checkout_service.py
yg menghitung ulang server-side) - nilainya cuma utk ditampilkan sbg
cadangan, tidak pernah dipakai utk debit stok/kasbon/apa pun yang
mengubah uang sungguhan."""

import uuid
from datetime import datetime
from decimal import Decimal

from pydantic import BaseModel


class ItemPesananIn(BaseModel):
    produk_id: uuid.UUID
    varian_id: uuid.UUID | None = None
    nama_produk: str
    qty: Decimal
    harga_satuan: Decimal


class PesananTersimpanIn(BaseModel):
    id: uuid.UUID  # WAJIB diisi HP - idempotency + dipakai hapus nanti
    outlet_id: uuid.UUID
    pelanggan_id: uuid.UUID | None = None
    tipe_order_id: uuid.UUID | None = None
    meja_id: uuid.UUID | None = None
    nomor_struk: str
    tanggal: datetime
    items: list[ItemPesananIn]
    catatan: str | None = None


class PesananTersimpanOut(BaseModel):
    id: uuid.UUID
    nomor_struk: str
    status: str
    total: Decimal


class BatalkanPesananIn(BaseModel):
    """Temuan#2 - alasan WAJIB diisi (dicek di pesanan_tersimpan_service.py,
    bukan cuma Pydantic required, supaya string kosong/whitespace juga
    ditolak). `disetujui_oleh` diisi HP kalau kasir sudah diminta PIN
    owner/manajer (lihat core/auth/pin_approval.dart) - server TETAP
    mengecek ulang izinnya, tidak pernah percaya klaim HP."""

    alasan: str
    disetujui_oleh: uuid.UUID | None = None
