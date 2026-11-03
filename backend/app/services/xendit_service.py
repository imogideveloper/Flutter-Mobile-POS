"""Pembayaran upgrade paket SUNGGUHAN lewat Xendit Invoice API - dibalik
dari keputusan awal F3.F.2 ("TIDAK ada pembayaran di app") atas permintaan
eksplisit pemilik produk: begitu bayar sukses, paket toko aktif otomatis
TANPA campur tangan admin manual.

Dua jalur konfirmasi pembayaran SENGAJA dua-duanya ada, bukan cuma salah
satu:
1. Webhook (`/payment/xendit/webhook`) - jalur UTAMA di produksi, real-time,
   tapi BUTUH backend bisa diakses dari internet (Xendit yang connect KE
   kita). Tidak akan pernah kepanggil kalau backend cuma jalan di
   localhost/dev sandbox tanpa tunnel (ngrok dkk).
2. Polling status (`GET .../status`) - app manggil endpoint INI (bukan
   Xendit yang connect ke kita) begitu user kembali dari halaman
   pembayaran Xendit, backend yang nanya ke Xendit (koneksi KELUAR, selalu
   jalan di mana pun backend di-deploy). Jaring pengaman kalau webhook
   belum/tidak sempat terpasang, BUKAN pengganti - produksi tetap wajib
   pasang webhook supaya aktivasi tidak bergantung user benar2 membuka
   lagi halaman Paket langganan.
"""

import base64
import uuid
from decimal import Decimal

import httpx
from fastapi import HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.models.outlet import Paket, PermintaanUpgrade
from app.schemas.langganan import AdminAktivasiLangganan, PermintaanUpgradeIn
from app.services.audit_service import catat_audit
from app.services.langganan_service import admin_aktivasi_langganan

_XENDIT_BASE_URL = "https://api.xendit.co"
# Wajib disertakan di SEMUA request ke /v3/payment_requests (API Payment
# Requests yang lebih baru, dipakai jalur QRIS/VA langsung - beda dari
# Invoice API /v2/invoices di atas yang tidak butuh header ini).
_XENDIT_API_VERSION = "2024-11-11"

# channel_code Xendit per bank VA yang didukung - daftar pendek yang umum
# dipakai toko kecil Indonesia, bukan daftar lengkap semua bank yang
# didukung Xendit (bisa ditambah lagi kapan saja tanpa migrasi DB, cuma
# baris Python).
BANK_VA_DIDUKUNG: dict[str, str] = {
    "bca": "BCA_VIRTUAL_ACCOUNT",
    "bni": "BNI_VIRTUAL_ACCOUNT",
    "bri": "BRI_VIRTUAL_ACCOUNT",
    "mandiri": "MANDIRI_VIRTUAL_ACCOUNT",
    "permata": "PERMATA_VIRTUAL_ACCOUNT",
}


def _auth_header() -> dict[str, str]:
    settings = get_settings()
    if not settings.xendit_api_key:
        raise HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE,
            "XENDIT_API_KEY belum diatur - upgrade paket lewat pembayaran belum bisa dipakai.",
        )
    token = base64.b64encode(f"{settings.xendit_api_key}:".encode()).decode()
    return {"Authorization": f"Basic {token}"}


def _auth_header_v3() -> dict[str, str]:
    return {**_auth_header(), "api-version": _XENDIT_API_VERSION}


async def buat_checkout_upgrade(
    db: AsyncSession, *, toko_id: uuid.UUID, body: PermintaanUpgradeIn, email_pembayar: str | None
) -> PermintaanUpgrade:
    """Buat baris PermintaanUpgrade + invoice Xendit sekaligus. Harga
    FLAT per tier paket (harga_bulanan/harga_tahunan) - TIDAK dikali
    jumlah_outlet (itu cuma kuota maksimal outlet yg dibolehkan paket
    itu, bukan harga per-outlet - konsisten dgn bagaimana maks_outlet
    dipakai di tempat lain, lihat fitur_service.py)."""

    permintaan, paket, harga = await _buat_permintaan_dasar(db, toko_id=toko_id, body=body)

    payload = {
        "external_id": str(permintaan.id),
        "amount": float(harga),
        "description": f"Upgrade paket {paket.nama} ({body.periode}) - Apps POS",
        "currency": "IDR",
        "invoice_duration": 24 * 60 * 60,  # 24 jam
    }
    if email_pembayar:
        payload["payer_email"] = email_pembayar

    async with httpx.AsyncClient(timeout=20) as client:
        resp = await client.post(
            f"{_XENDIT_BASE_URL}/v2/invoices", json=payload, headers=_auth_header()
        )
    if resp.status_code >= 400:
        raise HTTPException(
            status.HTTP_502_BAD_GATEWAY, f"Gagal membuat invoice Xendit: {resp.text}"
        )
    data = resp.json()

    permintaan.xendit_invoice_id = data["id"]
    permintaan.invoice_url = data["invoice_url"]
    await db.commit()
    await db.refresh(permintaan)
    return permintaan


async def _buat_permintaan_dasar(
    db: AsyncSession, *, toko_id: uuid.UUID, body: PermintaanUpgradeIn
) -> tuple[PermintaanUpgrade, Paket, Decimal]:
    """Bagian yang SAMA PERSIS dibutuhkan baik oleh QRIS maupun VA -
    validasi paket + hitung harga + bikin baris PermintaanUpgrade kosong
    (belum ada payment_request_id, diisi pemanggil sesudah ini)."""
    paket = await db.get(Paket, body.paket_tujuan_id)
    if paket is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Paket tujuan tidak ditemukan")

    harga = paket.harga_tahunan if body.periode == "tahunan" and paket.harga_tahunan is not None else paket.harga_bulanan
    harga = Decimal(str(harga))
    if harga <= 0:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST, "Paket ini gratis/tanpa harga - tidak perlu checkout pembayaran"
        )

    permintaan = PermintaanUpgrade(
        toko_id=toko_id,
        paket_tujuan_id=body.paket_tujuan_id,
        jumlah_outlet=body.jumlah_outlet,
        periode=body.periode,
        catatan=body.catatan,
        jumlah_bayar=harga,
    )
    db.add(permintaan)
    await db.flush()
    return permintaan, paket, harga


async def _buat_payment_request(
    db: AsyncSession,
    *,
    toko_id: uuid.UUID,
    body: PermintaanUpgradeIn,
    channel_code: str,
    metode_bayar: str,
) -> PermintaanUpgrade:
    """Satu jalur dipakai QRIS & VA - bedanya cuma channel_code (lihat
    Xendit Payment Requests API, /v3/payment_requests). Respons Xendit
    membawa `actions[].descriptor` yang beda tiap channel ("QR_STRING"
    utk QRIS, "VIRTUAL_ACCOUNT_NUMBER" utk VA) - diambil generik lewat
    [_ambil_action] drpd hardcode per channel di sini."""
    permintaan, paket, harga = await _buat_permintaan_dasar(db, toko_id=toko_id, body=body)

    payload = {
        "reference_id": str(permintaan.id),
        "type": "PAY",
        "country": "ID",
        "currency": "IDR",
        "request_amount": float(harga),
        "capture_method": "AUTOMATIC",
        "channel_code": channel_code,
        "channel_properties": {"display_name": "Apps POS"},
        "description": f"Upgrade paket {paket.nama} ({body.periode}) - Apps POS",
    }
    async with httpx.AsyncClient(timeout=20) as client:
        resp = await client.post(
            f"{_XENDIT_BASE_URL}/v3/payment_requests", json=payload, headers=_auth_header_v3()
        )
    if resp.status_code >= 400:
        raise HTTPException(
            status.HTTP_502_BAD_GATEWAY, f"Gagal membuat payment request Xendit: {resp.text}"
        )
    data = resp.json()

    permintaan.xendit_payment_request_id = data["payment_request_id"]
    permintaan.metode_bayar = metode_bayar
    permintaan.detail_bayar = {"actions": data.get("actions", [])}
    await db.commit()
    await db.refresh(permintaan)
    return permintaan


def _ambil_action(permintaan: PermintaanUpgrade, descriptor: str) -> str | None:
    aksi = (permintaan.detail_bayar or {}).get("actions", [])
    for item in aksi:
        if item.get("descriptor") == descriptor:
            return item.get("value")
    return None


async def buat_qris(
    db: AsyncSession, *, toko_id: uuid.UUID, body: PermintaanUpgradeIn
) -> tuple[PermintaanUpgrade, str]:
    """Balas (permintaan, qr_string) - qr_string dirender jadi gambar QR
    di Flutter (package qr_flutter, sama widget dgn bayar_qris_page.dart).
    CATATAN SANDBOX (bukan bug): di mode test, qr_string Xendit SENGAJA
    berupa placeholder yang TIDAK BISA discan e-wallet/m-banking asli -
    satu-satunya cara "membayar"-nya di sandbox lewat [simulasikan_bayar]
    di bawah, bukan scan sungguhan."""
    permintaan = await _buat_payment_request(
        db, toko_id=toko_id, body=body, channel_code="QRIS", metode_bayar="qris"
    )
    qr_string = _ambil_action(permintaan, "QR_STRING")
    if qr_string is None:
        raise HTTPException(status.HTTP_502_BAD_GATEWAY, "Xendit tidak mengembalikan QR string")
    return permintaan, qr_string


async def buat_va(
    db: AsyncSession, *, toko_id: uuid.UUID, body: PermintaanUpgradeIn, bank_code: str
) -> tuple[PermintaanUpgrade, str]:
    """Balas (permintaan, nomor_va). `bank_code` = key pendek di
    BANK_VA_DIDUKUNG (mis. "bca"), BUKAN channel_code Xendit mentah -
    validasi di sini supaya router tidak perlu tahu daftar channel_code
    Xendit sama sekali."""
    channel_code = BANK_VA_DIDUKUNG.get(bank_code.lower())
    if channel_code is None:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            f"Bank '{bank_code}' tidak didukung - pilihan: {', '.join(BANK_VA_DIDUKUNG)}",
        )
    permintaan = await _buat_payment_request(
        db, toko_id=toko_id, body=body, channel_code=channel_code, metode_bayar=channel_code.lower()
    )
    nomor_va = _ambil_action(permintaan, "VIRTUAL_ACCOUNT_NUMBER")
    if nomor_va is None:
        raise HTTPException(status.HTTP_502_BAD_GATEWAY, "Xendit tidak mengembalikan nomor VA")
    return permintaan, nomor_va


async def simulasikan_bayar(db: AsyncSession, permintaan: PermintaanUpgrade) -> None:
    """KHUSUS mode test Xendit (lihat catatan di buat_qris) - memicu
    Xendit "membayar" payment request ini secara artifisial. Dipanggil
    dari endpoint yang SENGAJA tetap ada di produksi (bukan di-exclude
    lewat flag ENVIRONMENT) krn Xendit sendiri yang menolak simulate call
    terhadap API key live (gagal aman di sisi Xendit, bukan di sini) -
    lihat diskusi di PR/laporan sesi ini kalau mau diperketat lagi nanti."""
    if permintaan.xendit_payment_request_id is None:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Permintaan ini bukan QRIS/VA (tidak ada payment_request)")
    async with httpx.AsyncClient(timeout=20) as client:
        resp = await client.post(
            f"{_XENDIT_BASE_URL}/v3/payment_requests/{permintaan.xendit_payment_request_id}/simulate",
            json={"amount": float(permintaan.jumlah_bayar)},
            headers=_auth_header_v3(),
        )
    if resp.status_code >= 400:
        raise HTTPException(status.HTTP_502_BAD_GATEWAY, f"Gagal simulasi pembayaran Xendit: {resp.text}")


async def _aktivasi_dari_permintaan(db: AsyncSession, permintaan: PermintaanUpgrade) -> None:
    """Dipanggil SETELAH dikonfirmasi lunas (dari webhook ATAU polling
    status) - sama logika aktivasi dgn jalur admin manual
    (admin_aktivasi_langganan), supaya tidak ada dua cara berbeda
    menentukan "paket toko ini sekarang apa"."""
    if permintaan.status == "selesai":
        return  # sudah pernah diaktivasi (webhook+polling bisa datang dobel) - idempotent
    await admin_aktivasi_langganan(
        db,
        AdminAktivasiLangganan(
            toko_id=permintaan.toko_id,
            paket_id=permintaan.paket_tujuan_id,
            jumlah_outlet=permintaan.jumlah_outlet,
            periode=permintaan.periode,
            berakhir=None,
        ),
    )
    permintaan.status = "selesai"
    await catat_audit(
        db,
        toko_id=permintaan.toko_id,
        pengguna_id=None,
        aksi="xendit_pembayaran_lunas",
        tabel="permintaan_upgrade",
        record_id=permintaan.id,
        data_baru={
            "paket_tujuan_id": str(permintaan.paket_tujuan_id),
            "jumlah_bayar": str(permintaan.jumlah_bayar),
            "xendit_invoice_id": permintaan.xendit_invoice_id,
        },
    )
    await db.commit()


async def cek_status_dan_aktivasi(db: AsyncSession, permintaan: PermintaanUpgrade) -> str:
    """Jalur POLLING (lihat catatan modul di atas) - backend yang nanya
    KELUAR ke Xendit, bukan nunggu dihubungi. Aman dipanggil berkali-kali
    (idempotent lewat _aktivasi_dari_permintaan). Dua kemungkinan sumber
    status, tergantung jalur mana yang dipakai bikin permintaan ini
    (payment_request/QRIS-VA jalur baru dicek duluan - itu yang dipakai
    modal metode bayar di app sekarang)."""
    if permintaan.status == "selesai":
        return "selesai"

    if permintaan.xendit_payment_request_id is not None:
        async with httpx.AsyncClient(timeout=20) as client:
            resp = await client.get(
                f"{_XENDIT_BASE_URL}/v3/payment_requests/{permintaan.xendit_payment_request_id}",
                headers=_auth_header_v3(),
            )
        if resp.status_code >= 400:
            raise HTTPException(status.HTTP_502_BAD_GATEWAY, f"Gagal cek status payment request Xendit: {resp.text}")
        status_xendit = resp.json().get("status")
        if status_xendit == "SUCCEEDED":
            await _aktivasi_dari_permintaan(db, permintaan)
            return "selesai"
        if status_xendit in ("EXPIRED", "FAILED", "CANCELED"):
            permintaan.status = "batal"
            await db.commit()
            return "batal"
        return permintaan.status

    if permintaan.xendit_invoice_id is not None:
        async with httpx.AsyncClient(timeout=20) as client:
            resp = await client.get(
                f"{_XENDIT_BASE_URL}/v2/invoices/{permintaan.xendit_invoice_id}", headers=_auth_header()
            )
        if resp.status_code >= 400:
            raise HTTPException(status.HTTP_502_BAD_GATEWAY, f"Gagal cek status invoice Xendit: {resp.text}")
        status_xendit = resp.json().get("status")
        if status_xendit == "PAID":
            await _aktivasi_dari_permintaan(db, permintaan)
            return "selesai"
        if status_xendit in ("EXPIRED",):
            permintaan.status = "batal"
            await db.commit()
            return "batal"
        return permintaan.status

    return permintaan.status


async def tandai_lunas_dari_webhook(db: AsyncSession, *, external_id: str) -> None:
    """Dipanggil dari router webhook SETELAH token callback Xendit
    diverifikasi (lihat routers/payment_xendit.py) - external_id yang
    dikirim Xendit SAMA PERSIS dgn permintaan.id yang kita set saat buat
    invoice (lihat buat_checkout_upgrade)."""
    try:
        permintaan_id = uuid.UUID(external_id)
    except ValueError:
        return  # bukan invoice dari modul ini (mis. invoice toko lain/fitur lain di masa depan) - abaikan diam2
    permintaan = await db.get(PermintaanUpgrade, permintaan_id)
    if permintaan is None:
        return
    await _aktivasi_dari_permintaan(db, permintaan)
