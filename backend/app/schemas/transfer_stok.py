import uuid
from decimal import Decimal

from pydantic import BaseModel


class ItemTransferIn(BaseModel):
    produk_id: uuid.UUID
    varian_id: uuid.UUID | None = None
    qty: Decimal


class ItemTransferOut(BaseModel):
    id: uuid.UUID
    produk_id: uuid.UUID
    nama_produk: str
    varian_id: uuid.UUID | None
    qty: Decimal


class TransferStokIn(BaseModel):
    dari_outlet_id: uuid.UUID
    ke_outlet_id: uuid.UUID
    nomor: str
    items: list[ItemTransferIn]


class TransferStokOut(BaseModel):
    id: uuid.UUID
    dari_outlet_id: uuid.UUID
    ke_outlet_id: uuid.UUID
    nomor: str
    status: str
    items: list[ItemTransferOut]
