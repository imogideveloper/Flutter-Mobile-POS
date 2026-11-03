"""Webhook Xendit - jalur UTAMA (real-time) buat aktivasi otomatis
begitu invoice lunas, lihat catatan lengkap di services/xendit_service.py
soal kenapa jalur polling JUGA ada sbg jaring pengaman. Endpoint ini
PUBLIK (dipanggil server Xendit, bukan app/kasir) - diamankan via header
`x-callback-token` yang dicocokkan ke XENDIT_WEBHOOK_TOKEN (diset sama
persis di dashboard Xendit > Settings > Webhooks), BUKAN via JWT toko."""

from fastapi import APIRouter, Depends, Header, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.core.db import get_db
from app.services.xendit_service import tandai_lunas_dari_webhook

router = APIRouter(prefix="/payment/xendit", tags=["payment"])


def _verifikasi_callback_token(x_callback_token: str | None = Header(default=None)) -> None:
    settings = get_settings()
    if not settings.xendit_webhook_token or x_callback_token != settings.xendit_webhook_token:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Callback token tidak valid")


@router.post("/webhook", dependencies=[Depends(_verifikasi_callback_token)])
async def webhook(body: dict, db: AsyncSession = Depends(get_db)) -> dict:
    # Dua bentuk payload mungkin masuk, tergantung jalur mana yang dipakai
    # bikin permintaan (lihat xendit_service.py):
    # 1. Invoice API (lama) - body RATA (flat): {"status": "PAID",
    #    "external_id": "..."}.
    # 2. Payment Requests API (baru, QRIS/VA) - body BERLAPIS:
    #    {"event": "payment.succeeded", "data": {"status": "SUCCEEDED",
    #    "reference_id": "..."}}.
    # Keduanya sama2 pakai id PermintaanUpgrade sbg
    # external_id/reference_id (lihat buat_checkout_upgrade/
    # _buat_payment_request) - diselaraskan ke satu pemanggilan di sini.
    data = body.get("data") if isinstance(body.get("data"), dict) else body
    status_xendit = data.get("status")
    permintaan_id = data.get("external_id") or data.get("reference_id")

    if status_xendit in ("PAID", "SUCCEEDED") and permintaan_id:
        await tandai_lunas_dari_webhook(db, external_id=permintaan_id)
    return {"received": True}
