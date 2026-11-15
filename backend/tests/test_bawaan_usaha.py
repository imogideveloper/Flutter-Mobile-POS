"""IMOGI no. 6: tipe pesanan bawaan dan biaya layanan 5% hanya untuk makan di
tempat (Kafe, Restoran), dibuat saat daftar dan ikut sync pull."""

import uuid
from datetime import UTC, datetime

import pytest
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.otp_store import InMemoryOtpStore
from app.models.akun import Pengguna
from app.models.order import TipeOrder, TipeOrderPajak
from app.models.promo import Pajak
from tests.conftest import buat_toko_siap_pakai


async def _daftar(client: AsyncClient, otp_store: InMemoryOtpStore, no_hp: str, jenis: str) -> dict:
    await otp_store.simpan(no_hp, "123456", 300)
    resp = await client.post(
        "/auth/otp/verify",
        json={
            "no_hp": no_hp,
            "kode": "123456",
            "device_uid": f"dev-{no_hp}",
            "nama_perangkat": "HP",
            "nama_toko": f"Toko {jenis}",
            "nama_pemilik": "Pemilik",
            "jenis_usaha": jenis,
            "pin": "482913",
        },
    )
    assert resp.status_code == 200, resp.text
    return resp.json()


@pytest.mark.parametrize("jenis", ["CAF", "RES"])
async def test_kafe_dan_restoran_mendapat_service_5_persen_hanya_untuk_makan_di_tempat(
    client: AsyncClient, db_session: AsyncSession, otp_store: InMemoryOtpStore, jenis: str
) -> None:
    body = await _daftar(client, otp_store, "0813" + ("1" if jenis == "CAF" else "2") * 8, jenis)
    toko_id = uuid.UUID(body["toko"]["id"])

    tipe = {
        t.nama: t
        for t in (await db_session.execute(select(TipeOrder).where(TipeOrder.toko_id == toko_id))).scalars().all()
    }
    assert set(tipe) == {"Makan di tempat", "Bawa pulang", "Delivery"}
    assert tipe["Makan di tempat"].kanal == "makan_di_tempat" and tipe["Makan di tempat"].pakai_meja is True
    assert tipe["Bawa pulang"].kanal == "bawa_pulang"
    assert tipe["Delivery"].kanal == "antar"

    service = (await db_session.execute(select(Pajak).where(Pajak.toko_id == toko_id))).scalar_one()
    assert service.tipe == "service" and float(service.persen) == 5 and service.aktif is True
    assert service.termasuk_harga is False

    tautan = (await db_session.execute(select(TipeOrderPajak))).scalars().all()
    assert [(t.tipe_order_id, t.pajak_id) for t in tautan] == [(tipe["Makan di tempat"].id, service.id)], (
        "service hanya ditautkan ke Makan di tempat, bukan Bawa pulang/Delivery"
    )


@pytest.mark.parametrize("jenis", ["CAT", "BRD", "FRZ", "BEV", "STL"])
async def test_jenis_usaha_lain_dapat_tipe_pesanan_tanpa_service_bawaan(
    client: AsyncClient, db_session: AsyncSession, otp_store: InMemoryOtpStore, jenis: str
) -> None:
    angka = {"CAT": "3", "BRD": "4", "FRZ": "5", "BEV": "6", "STL": "7"}[jenis]
    body = await _daftar(client, otp_store, "0813" + angka * 8, jenis)
    toko_id = uuid.UUID(body["toko"]["id"])

    jumlah_tipe = len((await db_session.execute(select(TipeOrder).where(TipeOrder.toko_id == toko_id))).scalars().all())
    assert jumlah_tipe == 3
    assert (await db_session.execute(select(Pajak).where(Pajak.toko_id == toko_id))).scalars().all() == []


async def test_tipe_pesanan_ikut_sync_pull(
    client: AsyncClient, db_session: AsyncSession, otp_store: InMemoryOtpStore
) -> None:
    body = await _daftar(client, otp_store, "08139999999", "CAF")
    headers = {"Authorization": f"Bearer {body['access_token']}"}

    resp = await client.get(
        "/sync/pull",
        headers=headers,
        params={"since": datetime(1970, 1, 1, tzinfo=UTC).isoformat(), "perangkat_id": body["perangkat_id"]},
    )
    assert resp.status_code == 200, resp.text
    hasil = resp.json()
    assert {t["nama"] for t in hasil["tipe_order"]} == {"Makan di tempat", "Bawa pulang", "Delivery"}
    makan = next(t for t in hasil["tipe_order"] if t["nama"] == "Makan di tempat")
    assert makan["kanal"] == "makan_di_tempat" and makan["pakai_meja"] is True and makan["aktif"] is True
    assert {p["nama"] for p in hasil["pajak"]} == {"Service Charge"}
    assert [t["tipe_order_id"] for t in hasil["tipe_order_pajak"]] == [makan["id"]]


async def test_toko_lama_tanpa_bawaan_tidak_terpengaruh(client: AsyncClient, db_session: AsyncSession) -> None:
    """Toko yang dibuat tanpa jalur pendaftaran (mis. fixture) tidak mendapat tipe pesanan otomatis."""
    toko = await buat_toko_siap_pakai(db_session)
    assert (await db_session.execute(select(TipeOrder).where(TipeOrder.toko_id == toko.toko.id))).scalars().all() == []
    assert (await db_session.execute(select(Pengguna).where(Pengguna.toko_id == toko.toko.id))).scalars().all()
