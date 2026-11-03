import uuid
from decimal import Decimal

from pydantic import BaseModel


class ItemRefundIn(BaseModel):
    item_transaksi_id: uuid.UUID
    qty: Decimal


class RefundIn(BaseModel):
    # id opsional - sama pola idempotency dgn CheckoutIn.id (D.5): kalau
    # diisi (refund yang lahir offline di HP, di-push belakangan), dipakai
    # utk mencegah refund dobel kalau push diulang. Kosong = refund ONLINE
    # biasa (dibuat langsung lewat UI, tidak lewat jalur offline-first).
    id: uuid.UUID | None = None
    alasan: str
    metode_bayar_id: uuid.UUID | None = None
    kembalikan_stok: bool = True
    items: list[ItemRefundIn]
    # Shift TEMPAT refund ini benar2 diproses (uang keluar dari laci) -
    # None = pakai transaksi.shift_id seperti sebelumnya (refund di shift
    # yang sama dgn transaksi aslinya, kasus paling umum). Tahap 3b-1
    # aturan #4: kas_seharusnya shift harus dikurangi refund TUNAI yang
    # terjadi DI shift itu, yang bisa berbeda dari shift transaksi asal
    # kalau refund-nya baru diproses belakangan.
    shift_id: uuid.UUID | None = None


class ItemRefundOut(BaseModel):
    item_transaksi_id: uuid.UUID
    qty: Decimal
    jumlah: Decimal


class ItemRefundableOut(BaseModel):
    """F3.D.1 - dipakai layar pilih item refund di Flutter: qty ASLI
    transaksi dikurangi yang sudah pernah direfund (bisa 0 kalau sudah
    habis) - UI tidak perlu menghitung sendiri, cukup pakai apa adanya."""

    item_transaksi_id: uuid.UUID
    nama_produk: str
    qty: Decimal
    harga_satuan: Decimal
    qty_sudah_direfund: Decimal
    sisa_bisa_direfund: Decimal


class RefundOut(BaseModel):
    id: uuid.UUID
    transaksi_id: uuid.UUID
    nomor: str
    alasan: str
    total: Decimal
    # Uang yang BENAR2 keluar dari refund ini (tahap 3b-1) - bisa < total
    # kalau transaksinya kasbon yang belum lunas (lihat refund_service.py).
    kas_dikembalikan: Decimal
    kembalikan_stok: bool
    items: list[ItemRefundOut]
    status_transaksi: str
    sisa_tagihan: Decimal
