import uuid
from datetime import date
from decimal import Decimal

from pydantic import BaseModel


class ItemOpnameIn(BaseModel):
    produk_id: uuid.UUID
    varian_id: uuid.UUID | None = None
    qty_fisik: Decimal


class ItemOpnameOut(BaseModel):
    id: uuid.UUID
    produk_id: uuid.UUID
    nama_produk: str
    varian_id: uuid.UUID | None
    qty_sistem: Decimal
    qty_fisik: Decimal
    selisih: Decimal


class StokOpnameIn(BaseModel):
    outlet_id: uuid.UUID
    nomor: str
    tanggal: date
    catatan: str | None = None
    items: list[ItemOpnameIn]


class StokOpnameOut(BaseModel):
    id: uuid.UUID
    outlet_id: uuid.UUID
    nomor: str
    tanggal: date
    status: str
    items: list[ItemOpnameOut]
