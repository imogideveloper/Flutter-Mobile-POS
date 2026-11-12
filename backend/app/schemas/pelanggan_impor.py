from datetime import date

from pydantic import BaseModel, Field

MAKS_BARIS_IMPOR_PELANGGAN = 500


class BarisPelangganImporIn(BaseModel):
    nama: str = Field(default="", max_length=150)
    no_hp: str | None = Field(default=None, max_length=30)
    email: str | None = Field(default=None, max_length=150)
    tanggal_lahir: date | None = None
    catatan: str | None = Field(default=None, max_length=500)


class ImporPelangganIn(BaseModel):
    baris: list[BarisPelangganImporIn] = Field(min_length=1, max_length=MAKS_BARIS_IMPOR_PELANGGAN)
    # true = hanya memeriksa (pratinjau), tidak menyimpan apa pun.
    simulasi: bool = False


class HasilBarisPelangganOut(BaseModel):
    nomor: int  # nomor baris 1-based dalam kiriman
    nama: str
    status: str  # "diterima" | "ditolak"
    pesan: str | None = None


class ImporPelangganOut(BaseModel):
    simulasi: bool
    diterima: int
    ditolak: int
    hasil: list[HasilBarisPelangganOut]
