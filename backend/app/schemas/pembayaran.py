import uuid
from datetime import datetime
from decimal import Decimal

from pydantic import BaseModel


class PembayaranIn(BaseModel):
    # id opsional - sama pola idempotency dgn CheckoutIn.id: kalau sudah
    # dibuat di HP (offline) lalu di-push, push ulang tidak boleh dobel.
    id: uuid.UUID | None = None
    # Shift TEMPAT uang ini diterima - WAJIB diisi eksplisit (bukan
    # "shift aktif saat ini"), krn cicilan offline bisa di-push setelah
    # shift yang menerimanya sudah ditutup (tahap 3b-1 aturan #4).
    shift_id: uuid.UUID
    metode_bayar_id: uuid.UUID
    jumlah: Decimal
    dibayar_pada: datetime | None = None
    # Temuan A.1 (tahap 5) - sama arti dgn SplitPembayaranLineIn.payload_gateway
    # (mis. penanda QRIS statis/manual) - dipakai utk pelunasan/cicilan
    # kasbon yang dibayar pakai QRIS statis.
    payload_gateway: dict | None = None


class PembayaranOut(BaseModel):
    id: uuid.UUID
    transaksi_id: uuid.UUID
    shift_id: uuid.UUID | None
    metode_bayar_id: uuid.UUID
    jumlah: Decimal
    jenis: str
    status: str
    dibayar_pada: datetime | None
    # Status transaksi SETELAH pembayaran ini diterapkan - supaya HP tidak
    # perlu panggilan terpisah utk tahu sisa_tagihan/status_bayar terbaru.
    sisa_tagihan: Decimal
    status_bayar: str

    model_config = {"from_attributes": True}
