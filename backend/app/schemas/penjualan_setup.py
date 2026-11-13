import uuid
from decimal import Decimal

from pydantic import BaseModel


class PajakIn(BaseModel):
    nama: str
    tipe: str = "pajak"  # pajak|service
    persen: Decimal
    termasuk_harga: bool = False
    urutan: int = 0


class PajakUpdateIn(BaseModel):
    nama: str | None = None
    tipe: str | None = None
    persen: Decimal | None = None
    termasuk_harga: bool | None = None
    urutan: int | None = None
    aktif: bool | None = None


class PajakOut(BaseModel):
    id: uuid.UUID
    nama: str
    tipe: str
    persen: Decimal
    termasuk_harga: bool
    urutan: int
    aktif: bool

    model_config = {"from_attributes": True}


class PromoIn(BaseModel):
    nama: str
    kode: str | None = None
    tipe: str  # persen|nominal
    nilai: Decimal
    cakupan: str = "transaksi"
    min_belanja: Decimal = Decimal("0")
    maks_diskon: Decimal | None = None
    # Promo ulang tahun (IMOGI no. 56): hanya untuk pelanggan yang berulang tahun hari ini.
    khusus_ulang_tahun: bool = False


class PromoUpdateIn(BaseModel):
    nama: str | None = None
    kode: str | None = None
    tipe: str | None = None
    nilai: Decimal | None = None
    cakupan: str | None = None
    min_belanja: Decimal | None = None
    maks_diskon: Decimal | None = None
    aktif: bool | None = None
    khusus_ulang_tahun: bool | None = None


class PromoOut(BaseModel):
    id: uuid.UUID
    nama: str
    kode: str | None
    tipe: str
    nilai: Decimal
    cakupan: str
    min_belanja: Decimal
    maks_diskon: Decimal | None
    aktif: bool
    khusus_ulang_tahun: bool = False

    model_config = {"from_attributes": True}


class IdsIn(BaseModel):
    """Tahap 5 B.3 - set lengkap id yang berlaku (replace-all, sama pola
    PUT /produk/{id}/grup-modifier/{grup_id} yang sudah ada) - dipakai utk
    promo_produk & promo_outlet."""

    ids: list[uuid.UUID] = []


class MetodeBayarIn(BaseModel):
    nama: str
    tipe: str  # tunai|qris|kartu|transfer|ewallet|lainnya
    butuh_gateway: bool = False
    masuk_laci: bool = False


class MetodeBayarUpdateIn(BaseModel):
    # nama/urutan digate fitur 'label_pembayaran' (tahap 4 bagian B.3) -
    # aktif/nonaktif TIDAK digate (dibutuhkan semua paket, mis. menyembunyikan
    # metode bayar yang tidak dipakai lagi).
    nama: str | None = None
    urutan: int | None = None
    aktif: bool | None = None


class MetodeBayarOut(BaseModel):
    id: uuid.UUID
    nama: str
    tipe: str
    butuh_gateway: bool
    masuk_laci: bool
    urutan: int
    aktif: bool

    model_config = {"from_attributes": True}
