"""F3.F.3 - endpoint admin PLATFORM (bukan owner toko) utk aktivasi
langganan dkk. Dilindungi API key statis dari environment (BUKAN JWT toko
- admin platform tidak punya toko_id/role_id sama sekali), dicek lewat
header `X-Admin-Api-Key`. Settings.admin_api_key default KOSONG = endpoint
ini SELALU menolak sampai operator benar2 set env var ADMIN_API_KEY
sendiri (gagal aman, sama prinsip dgn validasi produksi di config.py)."""

from fastapi import Header, HTTPException, status

from .config import get_settings


def verifikasi_admin_api_key(x_admin_api_key: str | None = Header(default=None)) -> None:
    settings = get_settings()
    if not settings.admin_api_key or x_admin_api_key != settings.admin_api_key:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Admin API key tidak valid")
