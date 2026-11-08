import uuid

from pydantic import BaseModel, Field, field_validator

from app.core.jenis_usaha import JENIS_USAHA_FNB, normalisasi_jenis_usaha


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

    @field_validator("jenis_usaha")
    @classmethod
    def _jenis_usaha_fnb(cls, nilai: str | None) -> str | None:
        """Hanya 7 jenis usaha Makanan & Minuman (kode IMOGI). Kosong = default;
        'fnb' dari klien lama dipetakan ke Kafe & Kedai Kopi."""
        if nilai is None:
            return None
        kode = normalisasi_jenis_usaha(nilai)
        if kode not in JENIS_USAHA_FNB:
            raise ValueError(f"jenis_usaha harus salah satu dari: {', '.join(JENIS_USAHA_FNB)}")
        return kode


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
