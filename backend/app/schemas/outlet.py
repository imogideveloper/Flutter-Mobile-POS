import uuid

from pydantic import BaseModel


class OutletIn(BaseModel):
    kode: str
    nama: str
    alamat: str | None = None
    no_hp: str | None = None


class OutletUpdateIn(BaseModel):
    nama: str | None = None
    alamat: str | None = None
    no_hp: str | None = None
    aktif: bool | None = None


class OutletOut(BaseModel):
    id: uuid.UUID
    toko_id: uuid.UUID
    kode: str
    nama: str
    alamat: str | None
    no_hp: str | None
    aktif: bool

    model_config = {"from_attributes": True}


class PengaturanOutletIn(BaseModel):
    header_struk: str | None = None
    footer_struk: str | None = None
    # 58 atau 80 (mm) - divalidasi di router (pakai Literal di sini bikin
    # "field tidak diisi" dan "field diisi nilai salah" susah dibedakan
    # lewat exclude_unset, makanya validasi manual).
    lebar_kertas_mm: int | None = None
    tampil_logo: bool | None = None
    pembulatan: int | None = None
    # Pengaturan operasional dasar (BUKAN fitur berbayar, tidak digate) -
    # sebelumnya kolom ini ADA di model+PengaturanOutletOut (terbaca lewat
    # GET) tapi TIDAK PERNAH bisa diubah (hilang dari PengaturanOutletIn),
    # jadi app Flutter tidak pernah bisa benar2 menyalakan/mematikannya.
    izinkan_stok_minus: bool | None = None
    # Masing2 digate fitur bernama sama (lihat routers/outlet.py) - HANYA
    # saat diisi True, bukan saat endpoint dipanggil (toko tanpa fitur itu
    # tetap boleh PATCH field lain, atau menutup field ini jadi False).
    struk_ringkas: bool | None = None
    pakai_nomor_antrean: bool | None = None


class PengaturanOutletOut(BaseModel):
    outlet_id: uuid.UUID
    header_struk: str | None
    footer_struk: str | None
    lebar_kertas_mm: int
    tampil_logo: bool
    pembulatan: int
    izinkan_stok_minus: bool
    wajib_buka_shift: bool
    struk_ringkas: bool
    pakai_nomor_antrean: bool

    model_config = {"from_attributes": True}
