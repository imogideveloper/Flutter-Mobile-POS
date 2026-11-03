import uuid
from decimal import Decimal

from pydantic import BaseModel


class ProdukVarianIn(BaseModel):
    nama: str
    sku: str | None = None
    barcode: str | None = None
    hpp: Decimal = Decimal("0")
    harga_jual: Decimal = Decimal("0")


class ProdukVarianUpdateIn(BaseModel):
    nama: str | None = None
    sku: str | None = None
    barcode: str | None = None
    hpp: Decimal | None = None
    harga_jual: Decimal | None = None
    aktif: bool | None = None


class ProdukVarianOut(BaseModel):
    id: uuid.UUID
    produk_id: uuid.UUID
    nama: str
    sku: str | None
    barcode: str | None
    hpp: Decimal
    harga_jual: Decimal
    aktif: bool

    model_config = {"from_attributes": True}


class GrupModifierIn(BaseModel):
    nama: str
    min_pilih: int = 0
    maks_pilih: int = 1


class GrupModifierUpdateIn(BaseModel):
    nama: str | None = None
    min_pilih: int | None = None
    maks_pilih: int | None = None


class GrupModifierOut(BaseModel):
    id: uuid.UUID
    nama: str
    min_pilih: int
    maks_pilih: int

    model_config = {"from_attributes": True}


class ModifierIn(BaseModel):
    nama: str
    harga_tambahan: Decimal = Decimal("0")
    urutan: int = 0


class ModifierUpdateIn(BaseModel):
    nama: str | None = None
    harga_tambahan: Decimal | None = None
    urutan: int | None = None
    aktif: bool | None = None


class ModifierOut(BaseModel):
    id: uuid.UUID
    grup_modifier_id: uuid.UUID
    nama: str
    harga_tambahan: Decimal
    urutan: int
    aktif: bool

    model_config = {"from_attributes": True}


class ResepIn(BaseModel):
    bahan_id: uuid.UUID
    varian_id: uuid.UUID | None = None
    qty: Decimal


class ResepUpdateIn(BaseModel):
    varian_id: uuid.UUID | None = None
    qty: Decimal | None = None


class ResepOut(BaseModel):
    id: uuid.UUID
    produk_id: uuid.UUID
    varian_id: uuid.UUID | None
    bahan_id: uuid.UUID
    nama_bahan: str
    qty: Decimal

    model_config = {"from_attributes": True}


class BundlingItemIn(BaseModel):
    produk_id: uuid.UUID
    varian_id: uuid.UUID | None = None
    qty: Decimal


class BundlingItemUpdateIn(BaseModel):
    varian_id: uuid.UUID | None = None
    qty: Decimal | None = None


class BundlingItemOut(BaseModel):
    id: uuid.UUID
    bundling_produk_id: uuid.UUID
    produk_id: uuid.UUID
    nama_produk: str
    varian_id: uuid.UUID | None
    qty: Decimal

    model_config = {"from_attributes": True}


class HargaGrosirIn(BaseModel):
    varian_id: uuid.UUID | None = None
    outlet_id: uuid.UUID | None = None
    min_qty: Decimal
    harga: Decimal


class HargaGrosirUpdateIn(BaseModel):
    min_qty: Decimal | None = None
    harga: Decimal | None = None


class HargaGrosirOut(BaseModel):
    id: uuid.UUID
    produk_id: uuid.UUID
    varian_id: uuid.UUID | None
    outlet_id: uuid.UUID | None
    min_qty: Decimal
    harga: Decimal

    model_config = {"from_attributes": True}


class HargaOutletIn(BaseModel):
    outlet_id: uuid.UUID
    varian_id: uuid.UUID | None = None
    harga_jual: Decimal


class HargaOutletUpdateIn(BaseModel):
    harga_jual: Decimal | None = None


class HargaOutletOut(BaseModel):
    id: uuid.UUID
    outlet_id: uuid.UUID
    produk_id: uuid.UUID
    varian_id: uuid.UUID | None
    harga_jual: Decimal

    model_config = {"from_attributes": True}


class ProdukPajakOut(BaseModel):
    produk_id: uuid.UUID
    pajak_id: uuid.UUID
    nama_pajak: str

    model_config = {"from_attributes": True}
