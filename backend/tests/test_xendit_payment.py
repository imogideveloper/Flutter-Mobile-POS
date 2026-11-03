"""Upgrade paket lewat pembayaran Xendit SUNGGUHAN (dibalik dari
keputusan awal F3.F.2 "tanpa pembayaran di app" - lihat
services/xendit_service.py). Panggilan HTTP ke Xendit di-mock total -
test ini TIDAK PERNAH menyentuh jaringan asli / akun Xendit sungguhan."""

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


class _FakeXenditClient:
    """Pengganti httpx.AsyncClient di dalam xendit_service - invoice_id
    dibuat deterministik dari external_id supaya test bisa menebak balik
    tanpa perlu state bersama tambahan."""

    def __init__(self, *, status_dibalas: str = "PAID", **kwargs) -> None:
        self._status_dibalas = status_dibalas

    async def __aenter__(self) -> "_FakeXenditClient":
        return self

    async def __aexit__(self, *exc) -> None:
        return None

    async def post(self, url: str, json: dict, headers: dict) -> _FakeResponse:
        assert "/v2/invoices" in url
        return _FakeResponse(
            200,
            {
                "id": f"inv-{json['external_id']}",
                "invoice_url": f"https://checkout-staging.xendit.co/web/inv-{json['external_id']}",
                "status": "PENDING",
            },
        )

    async def get(self, url: str, headers: dict) -> _FakeResponse:
        assert "/v2/invoices/inv-" in url
        return _FakeResponse(200, {"status": self._status_dibalas})


async def _ambil_paket_pro_berbayar(db_session: AsyncSession) -> Paket:
    """Seed test (app/core/seed.py) sengaja TIDAK mengisi harga paket
    (default 0 - fokus seed itu ke fitur/kuota, bukan harga) - checkout
    pembayaran butuh harga > 0, jadi diisi eksplisit di sini."""
    paket_pro = (await db_session.execute(select(Paket).where(Paket.nama == "Pro"))).scalar_one()
    paket_pro.harga_bulanan = Decimal("99000")
    await db_session.commit()
    await db_session.refresh(paket_pro)
    return paket_pro


@pytest.fixture
def _xendit_siap(monkeypatch: pytest.MonkeyPatch):
    """Pasang API key + webhook token palsu (dibutuhkan validasi di
    xendit_service/payment_xendit router), kembalikan helper utk
    memasang respons status GET invoice yang diinginkan tiap test."""
    monkeypatch.setenv("XENDIT_API_KEY", "xnd_development_test_dummy")
    monkeypatch.setenv("XENDIT_WEBHOOK_TOKEN", "token-rahasia-test")
    get_settings.cache_clear()

    status_box = {"status": "PAID"}

    def _buat_client(*args, **kwargs):
        return _FakeXenditClient(status_dibalas=status_box["status"])

    monkeypatch.setattr(httpx, "AsyncClient", _buat_client)

    def _set_status(status: str) -> None:
        status_box["status"] = status

    yield _set_status
    get_settings.cache_clear()


async def test_checkout_upgrade_membuat_invoice_dgn_harga_flat_per_tier(
    client: AsyncClient, db_session: AsyncSession, toko_a, _xendit_siap
) -> None:
    paket_pro = await _ambil_paket_pro_berbayar(db_session)

    resp = await client.post(
        "/langganan/checkout-upgrade",
        headers=toko_a.headers,
        json={"paket_tujuan_id": str(paket_pro.id), "jumlah_outlet": 3, "periode": "bulanan"},
    )
    assert resp.status_code == 201
    body = resp.json()
    assert body["invoice_url"] is not None
    assert body["status"] == "baru"
    # Harga FLAT per tier paket, BUKAN dikali jumlah_outlet (3) - lihat
    # catatan di xendit_service.py::buat_checkout_upgrade.
    assert Decimal(body["jumlah_bayar"]) == Decimal(str(paket_pro.harga_bulanan))


async def test_checkout_upgrade_paket_gratis_ditolak(
    client: AsyncClient, db_session: AsyncSession, toko_a, _xendit_siap
) -> None:
    paket_gratis = (await db_session.execute(select(Paket).where(Paket.nama == "Gratis"))).scalar_one()
    resp = await client.post(
        "/langganan/checkout-upgrade",
        headers=toko_a.headers,
        json={"paket_tujuan_id": str(paket_gratis.id)},
    )
    assert resp.status_code == 400


async def test_polling_status_lunas_mengaktifkan_paket_otomatis(
    client: AsyncClient, db_session: AsyncSession, toko_a, _xendit_siap
) -> None:
    paket_pro = await _ambil_paket_pro_berbayar(db_session)
    resp = await client.post(
        "/langganan/checkout-upgrade",
        headers=toko_a.headers,
        json={"paket_tujuan_id": str(paket_pro.id)},
    )
    permintaan_id = resp.json()["id"]

    _xendit_siap("PAID")
    resp = await client.get(
        f"/langganan/checkout-upgrade/{permintaan_id}/status", headers=toko_a.headers
    )
    assert resp.status_code == 200
    assert resp.json()["status"] == "selesai"

    # Paket toko BENAR2 berubah - bukan cuma status tiketnya.
    resp = await client.get("/langganan/saya", headers=toko_a.headers)
    assert resp.json()["paket_nama"] == "Pro"

    # Idempotent - panggil lagi tidak membuat baris Langganan dobel.
    jumlah_langganan_sebelum = len(
        (
            await db_session.execute(
                select(Langganan).where(Langganan.toko_id == toko_a.toko.id)
            )
        )
        .scalars()
        .all()
    )
    await client.get(f"/langganan/checkout-upgrade/{permintaan_id}/status", headers=toko_a.headers)
    jumlah_langganan_sesudah = len(
        (
            await db_session.execute(
                select(Langganan).where(Langganan.toko_id == toko_a.toko.id)
            )
        )
        .scalars()
        .all()
    )
    assert jumlah_langganan_sesudah == jumlah_langganan_sebelum


async def test_polling_status_kedaluwarsa_ditandai_batal_tanpa_aktivasi(
    client: AsyncClient, db_session: AsyncSession, toko_a, _xendit_siap
) -> None:
    paket_pro = await _ambil_paket_pro_berbayar(db_session)
    resp = await client.post(
        "/langganan/checkout-upgrade",
        headers=toko_a.headers,
        json={"paket_tujuan_id": str(paket_pro.id)},
    )
    permintaan_id = resp.json()["id"]

    _xendit_siap("EXPIRED")
    resp = await client.get(
        f"/langganan/checkout-upgrade/{permintaan_id}/status", headers=toko_a.headers
    )
    assert resp.json()["status"] == "batal"

    resp = await client.get("/langganan/saya", headers=toko_a.headers)
    assert resp.json()["paket_nama"] == "Gratis"  # tidak berubah


async def test_webhook_tanpa_token_ditolak(client: AsyncClient, db_session: AsyncSession) -> None:
    resp = await client.post("/payment/xendit/webhook", json={"status": "PAID", "external_id": "x"})
    assert resp.status_code == 401


async def test_webhook_dgn_token_benar_mengaktifkan_paket(
    client: AsyncClient, db_session: AsyncSession, toko_a, _xendit_siap
) -> None:
    paket_pro = await _ambil_paket_pro_berbayar(db_session)
    resp = await client.post(
        "/langganan/checkout-upgrade",
        headers=toko_a.headers,
        json={"paket_tujuan_id": str(paket_pro.id)},
    )
    permintaan_id = resp.json()["id"]

    resp = await client.post(
        "/payment/xendit/webhook",
        headers={"x-callback-token": "token-rahasia-test"},
        json={"status": "PAID", "external_id": permintaan_id},
    )
    assert resp.status_code == 200

    resp = await client.get("/langganan/saya", headers=toko_a.headers)
    assert resp.json()["paket_nama"] == "Pro"

    permintaan = await db_session.get(PermintaanUpgrade, uuid.UUID(permintaan_id))
    assert permintaan.status == "selesai"
