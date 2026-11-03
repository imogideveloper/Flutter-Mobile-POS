import uuid
from datetime import date, datetime
from decimal import Decimal

from pydantic import BaseModel


class TipeOrderIn(BaseModel):
    nama: str
    kanal: str = "langsung"
    pakai_meja: bool = False
    markup_persen: Decimal = Decimal("0")
    urutan: int = 0


class TipeOrderUpdateIn(BaseModel):
    nama: str | None = None
    kanal: str | None = None
    pakai_meja: bool | None = None
    markup_persen: Decimal | None = None
    urutan: int | None = None
    aktif: bool | None = None


class TipeOrderOut(BaseModel):
    id: uuid.UUID
    nama: str
    kanal: str
    pakai_meja: bool
    markup_persen: Decimal
    urutan: int
    aktif: bool

    model_config = {"from_attributes": True}


class MejaIn(BaseModel):
    nama: str
    area: str | None = None
    kapasitas: int | None = None
    urutan: int = 0


class MejaUpdateIn(BaseModel):
    nama: str | None = None
    area: str | None = None
    kapasitas: int | None = None
    urutan: int | None = None
    aktif: bool | None = None


class MejaOut(BaseModel):
    id: uuid.UUID
    outlet_id: uuid.UUID
    nama: str
    area: str | None
    kapasitas: int | None
    urutan: int
    aktif: bool

    model_config = {"from_attributes": True}


class TipeOrderPajakOut(BaseModel):
    tipe_order_id: uuid.UUID
    pajak_id: uuid.UUID
    nama_pajak: str


class StasiunDapurIn(BaseModel):
    nama: str
    printer_alamat: str | None = None
    lebar_kertas_mm: int = 58


class StasiunDapurOut(BaseModel):
    id: uuid.UUID
    outlet_id: uuid.UUID
    nama: str
    printer_alamat: str | None
    lebar_kertas_mm: int
    aktif: bool

    model_config = {"from_attributes": True}


class ItemPesananDapurOut(BaseModel):
    item_transaksi_id: uuid.UUID
    nama_produk: str
    qty: Decimal


class PesananDapurOut(BaseModel):
    id: uuid.UUID
    transaksi_id: uuid.UUID
    stasiun_dapur_id: uuid.UUID | None
    urutan_kirim: int
    status: str
    dicetak_pada: datetime | None
    siap_pada: datetime | None
    items: list[ItemPesananDapurOut]


class UbahStatusPesananDapurIn(BaseModel):
    status: str  # baru|dimasak|siap|disajikan|dibatalkan


class AntreanNomorOut(BaseModel):
    tanggal: date
    prefix: str
    nomor_terakhir: int
    nomor_lengkap: str
