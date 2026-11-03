"""Provider OTP - interface abstrak + implementasi mock (log ke stdout,
dipakai dev/test). Implementasi WhatsApp/SMS asli (lihat config.otp_provider)
adalah TODO - butuh kontrak dari provider resmi (mis. Twilio, Wablas,
Qontak) yang harus dicek dulu ke dokumentasi terbaru mereka sebelum
diimplementasikan; JANGAN anggap interface di bawah ini sudah cocok tanpa
verifikasi ulang."""

import random
from abc import ABC, abstractmethod

from app.core.config import get_settings


class OtpProvider(ABC):
    @abstractmethod
    async def kirim(self, no_hp: str, kode: str) -> None: ...


class MockOtpProvider(OtpProvider):
    async def kirim(self, no_hp: str, kode: str) -> None:
        print(f"[OTP MOCK] Kirim kode {kode} ke {no_hp} (TIDAK benar-benar terkirim)")


def buat_kode_otp() -> str:
    return f"{random.randint(0, 999999):06d}"


def get_otp_provider() -> OtpProvider:
    settings = get_settings()
    if settings.otp_provider == "mock":
        return MockOtpProvider()
    raise NotImplementedError(
        f"Provider OTP '{settings.otp_provider}' belum diimplementasikan - "
        "cek dokumentasi resmi provider itu sebelum mengimplementasikannya."
    )
