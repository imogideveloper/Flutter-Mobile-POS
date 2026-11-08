"""Fondasi katalog IMOGI (2026-11-08): jenis usaha Makanan & Minuman (7 kode IMOGI)
dan pencarian paket terendah lewat URUTAN, bukan nama - supaya backend tetap
jalan setelah katalog diganti ke Free/Starter/Professional/Enterprise."""

import pytest
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.jenis_usaha import JENIS_USAHA_FNB, normalisasi_jenis_usaha
from app.core.otp_store import InMemoryOtpStore
from app.models.outlet import Langganan, Paket, Toko
from app.services.fitur_service import paket_efektif


def _body(no_hp: str, **tambahan) -> dict:
    return {
        "no_hp": no_hp,
        "kode": "123456",
        "device_uid": f"device-{no_hp}",
        "nama_perangkat": "HP Kasir",
        "nama_toko": "Kedai Uji",
        "nama_pemilik": "Rina",
        "pin": "1234",
        **tambahan,
    }


def test_ada_tujuh_jenis_usaha_makanan_minuman() -> None:
    assert set(JENIS_USAHA_FNB) == {"CAF", "RES", "CAT", "BRD", "FRZ", "BEV", "STL"}
    assert JENIS_USAHA_FNB["CAF"] == "Kafe & Kedai Kopi"


@pytest.mark.parametrize(
    "masuk,keluar",
    [(None, "CAF"), ("", "CAF"), ("fnb", "CAF"), ("FNB", "CAF"), ("bev", "BEV"), (" STL ", "STL")],
)
def test_normalisasi_jenis_usaha(masuk, keluar) -> None:
    assert normalisasi_jenis_usaha(masuk) == keluar


@pytest.mark.parametrize("kode", ["CAF", "RES", "CAT", "BRD", "FRZ", "BEV", "STL"])
async def test_registrasi_menyimpan_jenis_usaha_fnb(
    client: AsyncClient, db_session: AsyncSession, otp_store: InMemoryOtpStore, kode: str
) -> None:
    await otp_store.simpan("081311112222", "123456", 300)
    resp = await client.post("/auth/otp/verify", json=_body("081311112222", jenis_usaha=kode))
    assert resp.status_code == 200
    assert resp.json()["toko"]["jenis_usaha"] == kode


async def test_registrasi_tanpa_jenis_usaha_default_kafe(
    client: AsyncClient, otp_store: InMemoryOtpStore
) -> None:
    await otp_store.simpan("081311112222", "123456", 300)
    resp = await client.post("/auth/otp/verify", json=_body("081311112222"))
    assert resp.status_code == 200
    assert resp.json()["toko"]["jenis_usaha"] == "CAF"


async def test_registrasi_jenis_usaha_lama_fnb_dipetakan_ke_kafe(
    client: AsyncClient, otp_store: InMemoryOtpStore
) -> None:
    await otp_store.simpan("081311112222", "123456", 300)
    resp = await client.post("/auth/otp/verify", json=_body("081311112222", jenis_usaha="fnb"))
    assert resp.status_code == 200
    assert resp.json()["toko"]["jenis_usaha"] == "CAF"


@pytest.mark.parametrize("kode", ["retail", "jasa", "laundry", "fashion", "XYZ"])
async def test_registrasi_jenis_usaha_di_luar_fnb_ditolak(
    client: AsyncClient, db_session: AsyncSession, otp_store: InMemoryOtpStore, kode: str
) -> None:
    await otp_store.simpan("081311112222", "123456", 300)
    resp = await client.post("/auth/otp/verify", json=_body("081311112222", jenis_usaha=kode))
    assert resp.status_code == 422
    assert (await db_session.execute(select(Toko))).scalars().all() == []


async def test_registrasi_dan_paket_efektif_tidak_bergantung_nama_paket(
    client: AsyncClient, db_session: AsyncSession, otp_store: InMemoryOtpStore
) -> None:
    """Ganti nama paket seperti migrasi 0010 (Gratis->Free, Pro->Starter, Bisnis->Enterprise)."""
    nama_baru = {"Gratis": "Free", "Pro": "Starter", "Bisnis": "Enterprise"}
    for paket in (await db_session.execute(select(Paket))).scalars().all():
        paket.nama = nama_baru[paket.nama]
    await db_session.commit()

    await otp_store.simpan("081311112222", "123456", 300)
    resp = await client.post("/auth/otp/verify", json=_body("081311112222", jenis_usaha="BEV"))
    assert resp.status_code == 200

    toko = (await db_session.execute(select(Toko))).scalar_one()
    langganan = (await db_session.execute(select(Langganan).where(Langganan.toko_id == toko.id))).scalar_one()
    paket = await db_session.get(Paket, langganan.paket_id)
    assert paket.nama == "Free" and paket.urutan == 0

    # Tanpa langganan aktif pun, paket efektif = paket TERENDAH, walau namanya bukan "Gratis".
    langganan.status = "batal"
    await db_session.commit()
    assert (await paket_efektif(db_session, toko.id)).nama == "Free"
