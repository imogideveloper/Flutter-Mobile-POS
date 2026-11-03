"""QRIS & VA LANGSUNG di app (tanpa redirect browser) - lewat Xendit
Payment Requests API (/v3/payment_requests), beda dari Invoice API lama
yang diuji di test_xendit_payment.py. Panggilan HTTP ke Xendit di-mock
total - test ini TIDAK PERNAH menyentuh jaringan asli / akun Xendit
sungguhan."""

import uuid
from decimal import Decimal

import httpx
import pytest
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.models.outlet import Langganan, Paket, PermintaanUpgrade


class _FakeResponse:
    def __init__(self, status_code: int, payload: dict) -> None:
        self.status_code = status_code
        self._payload = payload
        self.text = str(payload)

    def json(self) -> dict:
        return self._payload


class _FakeXenditPaymentRequestClient:
    """Pengganti httpx.AsyncClient di dalam xendit_service - payment_request_id
    dibuat deterministik dari reference_id, actions dibalas sesuai channel_code
    yang dikirim supaya test bisa menebak balik qr_string/nomor VA."""

    def __init__(self, *, status_dibalas: str = "SUCCEEDED", **kwargs) -> None:
        self._status_dibalas = status_dibalas

    async def __aenter__(self) -> "_FakeXenditPaymentRequestClient":
        return self

    async def __aexit__(self, *exc) -> None:
        return None

    async def post(self, url: str, json: dict, headers: dict) -> _FakeResponse:
        assert headers.get("api-version") == "2024-11-11"
        if url.endswith("/simulate"):
            return _FakeResponse(200, {"status": "SUCCEEDED"})
        assert "/v3/payment_requests" in url
        pr_id = f"pr-{json['reference_id']}"
        channel_code = json["channel_code"]
        if channel_code == "QRIS":
            actions = [{"descriptor": "QR_STRING", "value": f"qr-string-{pr_id}"}]
        else:
            actions = [{"descriptor": "VIRTUAL_ACCOUNT_NUMBER", "value": f"8808{pr_id}"}]
        return _FakeResponse(
            200, {"payment_request_id": pr_id, "status": "REQUIRES_ACTION", "actions": actions}
        )

    async def get(self, url: str, headers: dict) -> _FakeResponse:
        assert headers.get("api-version") == "2024-11-11"
        assert "/v3/payment_requests/pr-" in url
        return _FakeResponse(200, {"status": self._status_dibalas})


async def _ambil_paket_pro_berbayar(db_session: AsyncSession) -> Paket:
    paket_pro = (await db_session.execute(select(Paket).where(Paket.nama == "Pro"))).scalar_one()
    paket_pro.harga_bulanan = Decimal("99000")
    await db_session.commit()
    await db_session.refresh(paket_pro)
    return paket_pro


@pytest.fixture
def _xendit_siap(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("XENDIT_API_KEY", "xnd_development_test_dummy")
    monkeypatch.setenv("XENDIT_WEBHOOK_TOKEN", "token-rahasia-test")
    get_settings.cache_clear()

    status_box = {"status": "SUCCEEDED"}

    def _buat_client(*args, **kwargs):
        return _FakeXenditPaymentRequestClient(status_dibalas=status_box["status"])

    monkeypatch.setattr(httpx, "AsyncClient", _buat_client)

    def _set_status(status: str) -> None:
        status_box["status"] = status

    yield _set_status
    get_settings.cache_clear()


async def test_checkout_qris_mengembalikan_qr_string(
    client: AsyncClient, db_session: AsyncSession, toko_a, _xendit_siap
) -> None:
    paket_pro = await _ambil_paket_pro_berbayar(db_session)
    resp = await client.post(
        "/langganan/checkout-upgrade/qris",
        headers=toko_a.headers,
        json={"paket_tujuan_id": str(paket_pro.id), "jumlah_outlet": 3, "periode": "bulanan"},
    )
    assert resp.status_code == 201
    body = resp.json()
    assert body["qr_string"].startswith("qr-string-pr-")
    assert body["status"] == "baru"
    # Harga FLAT per tier, bukan dikali jumlah_outlet.
    assert Decimal(str(body["jumlah_bayar"])) == Decimal(str(paket_pro.harga_bulanan))


async def test_checkout_va_mengembalikan_nomor_va(
    client: AsyncClient, db_session: AsyncSession, toko_a, _xendit_siap
) -> None:
    paket_pro = await _ambil_paket_pro_berbayar(db_session)
    resp = await client.post(
        "/langganan/checkout-upgrade/va",
        headers=toko_a.headers,
        json={"paket_tujuan_id": str(paket_pro.id), "bank_code": "bca"},
    )
    assert resp.status_code == 201
    body = resp.json()
    assert body["bank_code"] == "bca"
    assert body["nomor_va"].startswith("8808pr-")


async def test_checkout_va_bank_tidak_didukung_ditolak(
    client: AsyncClient, db_session: AsyncSession, toko_a, _xendit_siap
) -> None:
    paket_pro = await _ambil_paket_pro_berbayar(db_session)
    resp = await client.post(
        "/langganan/checkout-upgrade/va",
        headers=toko_a.headers,
        json={"paket_tujuan_id": str(paket_pro.id), "bank_code": "bank_tidak_ada"},
    )
    assert resp.status_code == 400


async def test_simulasi_bayar_qris_lalu_status_mengaktifkan_paket(
    client: AsyncClient, db_session: AsyncSession, toko_a, _xendit_siap
) -> None:
    paket_pro = await _ambil_paket_pro_berbayar(db_session)
    resp = await client.post(
        "/langganan/checkout-upgrade/qris",
        headers=toko_a.headers,
        json={"paket_tujuan_id": str(paket_pro.id)},
    )
    permintaan_id = resp.json()["id"]

    resp = await client.post(
        f"/langganan/checkout-upgrade/{permintaan_id}/simulasi", headers=toko_a.headers
    )
    assert resp.status_code == 200
    assert resp.json()["status"] == "selesai"

    resp = await client.get("/langganan/saya", headers=toko_a.headers)
    assert resp.json()["paket_nama"] == "Pro"

    permintaan = await db_session.get(PermintaanUpgrade, uuid.UUID(permintaan_id))
    assert permintaan.status == "selesai"


async def test_polling_status_va_kedaluwarsa_ditandai_batal(
    client: AsyncClient, db_session: AsyncSession, toko_a, _xendit_siap
) -> None:
    paket_pro = await _ambil_paket_pro_berbayar(db_session)
    resp = await client.post(
        "/langganan/checkout-upgrade/va",
        headers=toko_a.headers,
        json={"paket_tujuan_id": str(paket_pro.id), "bank_code": "bni"},
    )
    permintaan_id = resp.json()["id"]

    _xendit_siap("EXPIRED")
    resp = await client.get(
        f"/langganan/checkout-upgrade/{permintaan_id}/status", headers=toko_a.headers
    )
    assert resp.json()["status"] == "batal"

    resp = await client.get("/langganan/saya", headers=toko_a.headers)
    assert resp.json()["paket_nama"] == "Gratis"


async def test_webhook_bentuk_payment_request_mengaktifkan_paket(
    client: AsyncClient, db_session: AsyncSession, toko_a, _xendit_siap
) -> None:
    paket_pro = await _ambil_paket_pro_berbayar(db_session)
    resp = await client.post(
        "/langganan/checkout-upgrade/qris",
        headers=toko_a.headers,
        json={"paket_tujuan_id": str(paket_pro.id)},
    )
    permintaan_id = resp.json()["id"]

    resp = await client.post(
        "/payment/xendit/webhook",
        headers={"x-callback-token": "token-rahasia-test"},
        json={"event": "payment.succeeded", "data": {"status": "SUCCEEDED", "reference_id": permintaan_id}},
    )
    assert resp.status_code == 200

    resp = await client.get("/langganan/saya", headers=toko_a.headers)
    assert resp.json()["paket_nama"] == "Pro"

    # Idempotent - panggil lagi tidak bikin baris Langganan dobel.
    jumlah_sebelum = len(
        (await db_session.execute(select(Langganan).where(Langganan.toko_id == toko_a.toko.id)))
        .scalars()
        .all()
    )
    await client.post(
        "/payment/xendit/webhook",
        headers={"x-callback-token": "token-rahasia-test"},
        json={"event": "payment.succeeded", "data": {"status": "SUCCEEDED", "reference_id": permintaan_id}},
    )
    jumlah_sesudah = len(
        (await db_session.execute(select(Langganan).where(Langganan.toko_id == toko_a.toko.id)))
        .scalars()
        .all()
    )
    assert jumlah_sesudah == jumlah_sebelum


async def test_simulasi_pada_permintaan_invoice_lama_ditolak(
    client: AsyncClient, db_session: AsyncSession, toko_a, _xendit_siap
) -> None:
    """simulasikan_bayar hanya berlaku utk jalur payment_request (QRIS/VA
    baru) - permintaan dari jalur invoice lama tidak punya
    xendit_payment_request_id sama sekali."""
    paket_pro = await _ambil_paket_pro_berbayar(db_session)
    permintaan = PermintaanUpgrade(
        toko_id=toko_a.toko.id,
        paket_tujuan_id=paket_pro.id,
        jumlah_outlet=1,
        periode="bulanan",
        jumlah_bayar=Decimal("99000"),
        xendit_invoice_id="inv-lama-123",
    )
    db_session.add(permintaan)
    await db_session.commit()
    await db_session.refresh(permintaan)

    resp = await client.post(
        f"/langganan/checkout-upgrade/{permintaan.id}/simulasi", headers=toko_a.headers
    )
    assert resp.status_code == 400
