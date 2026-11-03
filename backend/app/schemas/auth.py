import uuid

from pydantic import BaseModel, Field


class OtpRequestIn(BaseModel):
    no_hp: str = Field(min_length=8, max_length=20)


class OtpRequestOut(BaseModel):
    expires_in: int


class OtpVerifyIn(BaseModel):
    no_hp: str = Field(min_length=8, max_length=20)
    kode: str = Field(min_length=6, max_length=6)
    device_uid: str
    nama_perangkat: str
    platform: str | None = None
    # Hanya dipakai saat no_hp BELUM terdaftar (registrasi toko baru) - lihat
    # app/routers/auth.py untuk aturan lengkapnya.
    nama_toko: str | None = None
    jenis_usaha: str | None = None
    nama_pemilik: str | None = None
    # Dua kegunaan tergantung no_hp sudah terdaftar atau belum: toko baru
    # = PIN awal akun Owner, toko yang sudah ada = "lupa PIN kasir" (reset
    # PIN device lewat OTP, lihat app/routers/auth.py::verifikasi_otp).
    pin: str | None = Field(default=None, min_length=4, max_length=6)


class TokoOut(BaseModel):
    id: uuid.UUID
    nama: str
    jenis_usaha: str | None


class OutletOut(BaseModel):
    id: uuid.UUID
    nama: str
    kode: str


class PenggunaOut(BaseModel):
    id: uuid.UUID
    nama: str
    role_id: uuid.UUID


class AuthOut(BaseModel):
    access_token: str
    refresh_token: str
    toko: TokoOut
    outlet: OutletOut
    pengguna: PenggunaOut
    # Device yang baru di-pairing/diperbarui oleh request ini - client
    # butuh id ini utk `perangkat_id` di /sync/push, tapi _upsert_perangkat
    # sebelumnya tidak pernah mengembalikannya ke response sama sekali.
    perangkat_id: uuid.UUID


class RefreshIn(BaseModel):
    refresh_token: str


class RefreshOut(BaseModel):
    access_token: str


class PinLoginIn(BaseModel):
    """Tahap 5b - login PIN ONLINE (beda dari ganti-kasir harian lokal di
    HP) - menghasilkan token ATAS NAMA karyawan ybs (bukan token device/
    Owner), supaya panggilan online (refund, layar kelola) dicek izinnya
    berdasarkan identitas karyawan yang sebenarnya."""

    perangkat_id: uuid.UUID
    pengguna_id: uuid.UUID
    pin: str = Field(min_length=6, max_length=6)


class PinLoginOut(BaseModel):
    access_token: str
    refresh_token: str
    pengguna: PenggunaOut
    perangkat_id: uuid.UUID
