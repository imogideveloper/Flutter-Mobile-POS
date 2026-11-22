import uuid
from decimal import Decimal

from pydantic import BaseModel, Field

MAKS_BARIS_IMPOR = 500


class BarisImporIn(BaseModel):
    nama: str = Field(default="", max_length=150)
    kategori: str | None = Field(default=None, max_length=100)
    # None = kolom kosong: produk baru dianggap 0, produk lama (mode perbarui) tidak diubah.
    harga_jual: Decimal | None = None
    hpp: Decimal | None = None
    sku: str | None = Field(default=None, max_length=50)
    barcode: str | None = Field(default=None, max_length=50)
    deskripsi: str | None = Field(default=None, max_length=500)
    # Stok awal produk BARU di outlet kiriman; diabaikan pada produk yang diperbarui.
    stok_awal: Decimal | None = None


class ImporProdukIn(BaseModel):
    baris: list[BarisImporIn] = Field(min_length=1, max_length=MAKS_BARIS_IMPOR)
    # true = hanya memeriksa (pratinjau), tidak menyimpan apa pun.
    simulasi: bool = False
    # true = baris dengan SKU/barcode milik produk yang sudah ada memperbarui produk itu (bukan ditolak).
    perbarui_yang_ada: bool = False
    # Outlet tujuan stok awal; wajib bila ada baris dengan stok_awal.
    outlet_id: uuid.UUID | None = None


class HasilBarisImporOut(BaseModel):
    nomor: int  # nomor baris 1-based dalam kiriman
    nama: str
    status: str  # "diterima" | "diperbarui" | "ditolak"
    pesan: str | None = None


class ImporProdukOut(BaseModel):
    simulasi: bool
    diterima: int  # baru + diperbarui
    diperbarui: int = 0
    ditolak: int
    kategori_baru: list[str]
    hasil: list[HasilBarisImporOut]
