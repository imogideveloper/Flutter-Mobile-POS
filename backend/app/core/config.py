from decimal import Decimal
from functools import lru_cache
from typing import Literal

from pydantic import model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

DEFAULT_JWT_SECRET = "Cao123456!"


class Settings(BaseSettings):
    """Konfigurasi aplikasi.

    Nilai di bawah hanya default untuk development lokal.
    Nilai sebenarnya dibaca dari file .env atau environment variable
    (nama variabel = nama field dalam huruf besar, mis. DATABASE_URL).
    """

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    # --- Aplikasi ---
    app_name: str = "Apps POS API"
    environment: Literal["development", "staging", "production"] = "development"

    # --- Database & cache ---
    # PostgreSQL lokal jalan di port 5433 (lihat DBeaver)
    database_url: str = "postgresql+asyncpg://pos:pos@localhost:5433/pos"
    database_echo: bool = False  # True = tampilkan semua query SQL di log
    database_pool_size: int = 10
    redis_url: str = "redis://localhost:6379/0"

    # --- Auth ---
    jwt_secret: str = DEFAULT_JWT_SECRET
    jwt_algorithm: str = "HS256"
    access_token_expire_minutes: int = 30
    refresh_token_expire_days: int = 30

    # --- Admin platform (F3.F) - BUKAN JWT toko, dipakai endpoint admin
    # internal (aktivasi langganan dkk) lewat header statis X-Admin-Api-Key.
    # Default KOSONG = endpoint admin selalu menolak (gagal aman) sampai
    # operator benar2 set env var ADMIN_API_KEY sendiri - lihat
    # app/core/admin_auth.py.
    admin_api_key: str = ""

    # --- Pesanan tersimpan (F3.E) - temuan#2: pembatalan di atas nilai ini
    # oleh Kasir wajib approval PIN owner/manajer (izin
    # `transaksi.batal_pesanan`). Default Rp0 = SELALU wajib approval utk
    # pesanan yang totalnya > 0 - lihat app/services/pesanan_tersimpan_service.py.
    batas_approval_batal_pesanan: Decimal = Decimal("0")

    # --- OTP ---
    otp_expire_seconds: int = 300
    otp_provider: Literal["mock", "whatsapp", "sms"] = "mock"  # lihat app/services/otp_service.py

    # --- Payment gateway ---
    payment_provider: Literal["mock", "midtrans", "xendit"] = "mock"
    midtrans_server_key: str = ""
    midtrans_is_production: bool = False
    xendit_api_key: str = ""
    # Verification Token dari dashboard Xendit > Settings > Webhooks -
    # dicocokkan ke header `x-callback-token` tiap webhook masuk (lihat
    # routers/payment_xendit.py). Kosong = webhook SELALU ditolak (gagal
    # aman) - jalur polling (lihat xendit_service.py) tetap jalan tanpa
    # ini, cuma webhook real-time yang butuh.
    xendit_webhook_token: str = ""

    # --- Penyimpanan file (foto produk, logo) ---
    s3_bucket: str = ""
    s3_region: str = "ap-southeast-3"  # AWS Jakarta
    s3_endpoint_url: str | None = None  # isi untuk MinIO saat development

    @property
    def is_production(self) -> bool:
        return self.environment == "production"

    @model_validator(mode="after")
    def _cek_konfigurasi_produksi(self) -> "Settings":
        """Gagal saat startup kalau konfigurasi produksi tidak aman."""
        if not self.is_production:
            return self

        masalah: list[str] = []
        if self.jwt_secret == DEFAULT_JWT_SECRET or len(self.jwt_secret) < 32:
            masalah.append("JWT_SECRET masih default atau kurang dari 32 karakter")
        if "pos:pos@" in self.database_url:
            masalah.append("DATABASE_URL masih memakai user/password development")
        if self.otp_provider == "mock":
            masalah.append("OTP_PROVIDER masih 'mock'")
        if self.payment_provider == "mock":
            masalah.append("PAYMENT_PROVIDER masih 'mock'")
        if self.payment_provider == "midtrans" and not self.midtrans_server_key:
            masalah.append("MIDTRANS_SERVER_KEY kosong")
        if self.payment_provider == "xendit" and not self.xendit_api_key:
            masalah.append("XENDIT_API_KEY kosong")

        if masalah:
            raise ValueError("Konfigurasi produksi tidak aman: " + "; ".join(masalah))
        return self


@lru_cache
def get_settings() -> Settings:
    return Settings()