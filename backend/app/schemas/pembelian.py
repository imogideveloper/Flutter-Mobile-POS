import uuid
from datetime import date
from decimal import Decimal

from pydantic import BaseModel


class SupplierIn(BaseModel):
    nama: str
    kontak: str | None = None
    no_hp: str | None = None
    email: str | None = None
    alamat: str | None = None


class SupplierOut(BaseModel):
    id: uuid.UUID
    nama: str
    kontak: str | None
    no_hp: str | None
    email: str | None
    alamat: str | None

    model_config = {"from_attributes": True}


class ItemPembelianIn(BaseModel):
    produk_id: uuid.UUID
    varian_id: uuid.UUID | None = None
    qty: Decimal
    harga_satuan: Decimal = Decimal("0")


class ItemPembelianOut(BaseModel):
    id: uuid.UUID
    produk_id: uuid.UUID
    nama_produk: str
    varian_id: uuid.UUID | None
    qty: Decimal
    harga_satuan: Decimal
    subtotal: Decimal


class PembelianIn(BaseModel):
    outlet_id: uuid.UUID
    supplier_id: uuid.UUID | None = None
    nomor: str
    tanggal: date
    catatan: str | None = None
    items: list[ItemPembelianIn]


class PembelianOut(BaseModel):
    id: uuid.UUID
    outlet_id: uuid.UUID
    supplier_id: uuid.UUID | None
    nomor: str
    tanggal: date
    status: str
    subtotal: Decimal
    total: Decimal
    status_bayar: str
    items: list[ItemPembelianOut]
