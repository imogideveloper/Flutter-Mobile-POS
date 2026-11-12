import uuid
from datetime import date, datetime
from typing import Literal

from pydantic import BaseModel, Field

KategoriPengeluaran = Literal[
    "belanja_bahan", "gas_lpg", "kemasan", "gaji", "sewa", "listrik_air", "pemasaran", "perawatan", "lainnya"
]


class PengeluaranIn(BaseModel):
    # id dari klien (UUID) supaya pengiriman ulang tidak menggandakan catatan (idempoten).
    id: uuid.UUID | None = None
    outlet_id: uuid.UUID | None = None
    tanggal: date
    kategori: KategoriPengeluaran
    jumlah: float = Field(gt=0, le=99_999_999_999)
    catatan: str | None = Field(default=None, max_length=300)


class PengeluaranOut(BaseModel):
    id: uuid.UUID
    outlet_id: uuid.UUID | None
    tanggal: date
    kategori: str
    jumlah: float
    catatan: str | None
    dibuat_oleh: uuid.UUID | None
    created_at: datetime

    model_config = {"from_attributes": True}


class RingkasanKategoriOut(BaseModel):
    kategori: str
    total: float


class DaftarPengeluaranOut(BaseModel):
    total: float
    per_kategori: list[RingkasanKategoriOut]
    item: list[PengeluaranOut]
