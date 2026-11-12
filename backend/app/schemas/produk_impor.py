from decimal import Decimal

from pydantic import BaseModel, Field

MAKS_BARIS_IMPOR = 500


class BarisImporIn(BaseModel):
    nama: str = Field(default="", max_length=150)
    kategori: str | None = Field(default=None, max_length=100)
    harga_jual: Decimal = Decimal("0")
    hpp: Decimal = Decimal("0")
    sku: str | None = Field(default=None, max_length=50)
    barcode: str | None = Field(default=None, max_length=50)
    deskripsi: str | None = Field(default=None, max_length=500)


class ImporProdukIn(BaseModel):
    baris: list[BarisImporIn] = Field(min_length=1, max_length=MAKS_BARIS_IMPOR)
    # true = hanya memeriksa (pratinjau), tidak menyimpan apa pun.
    simulasi: bool = False


class HasilBarisImporOut(BaseModel):
    nomor: int  # nomor baris 1-based dalam kiriman
    nama: str
    status: str  # "diterima" | "ditolak"
    pesan: str | None = None


class ImporProdukOut(BaseModel):
    simulasi: bool
    diterima: int
    ditolak: int
    kategori_baru: list[str]
    hasil: list[HasilBarisImporOut]
