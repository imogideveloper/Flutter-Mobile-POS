import uuid
from decimal import Decimal

from pydantic import BaseModel


class KategoriIn(BaseModel):
    nama: str
    warna: str | None = None
    urutan: int = 0


class KategoriUpdateIn(BaseModel):
    nama: str | None = None
    warna: str | None = None
    urutan: int | None = None


class KategoriOut(BaseModel):
    id: uuid.UUID
    nama: str
    warna: str | None
    urutan: int

    model_config = {"from_attributes": True}


class SatuanIn(BaseModel):
    nama: str
    singkatan: str


class SatuanOut(BaseModel):
    id: uuid.UUID
    nama: str
    singkatan: str

    model_config = {"from_attributes": True}


class ProdukIn(BaseModel):
    kategori_id: uuid.UUID | None = None
    satuan_id: uuid.UUID | None = None
    sku: str | None = None
    barcode: str | None = None
    nama: str
    deskripsi: str | None = None
    tipe: str = "barang"
    lacak_stok: bool = True
    hpp: Decimal = Decimal("0")
    harga_jual: Decimal = Decimal("0")
    aktif: bool = True


class ProdukUpdateIn(BaseModel):
    kategori_id: uuid.UUID | None = None
    satuan_id: uuid.UUID | None = None
    sku: str | None = None
    barcode: str | None = None
    nama: str | None = None
    deskripsi: str | None = None
    hpp: Decimal | None = None
    harga_jual: Decimal | None = None
    aktif: bool | None = None


class ProdukOut(BaseModel):
    id: uuid.UUID
    toko_id: uuid.UUID
    kategori_id: uuid.UUID | None
    satuan_id: uuid.UUID | None
    sku: str | None
    barcode: str | None
    nama: str
    deskripsi: str | None
    tipe: str
    lacak_stok: bool
    hpp: Decimal
    harga_jual: Decimal
    aktif: bool

    model_config = {"from_attributes": True}
