"""Promo ulang tahun (IMOGI no. 56): penanda promo, tanggal lahir pelanggan, dan sync ke HP."""

from datetime import UTC, date, datetime

from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from tests.conftest import buat_perangkat, buat_toko_siap_pakai

EPOCH = datetime(1970, 1, 1, tzinfo=UTC).isoformat()


def _promo(**lain) -> dict:
    return {"nama": "Diskon Ulang Tahun", "tipe": "persen", "nilai": 20, **lain}


async def test_promo_biasa_tidak_khusus_ulang_tahun_dan_tidak_digerbang(client: AsyncClient, db_session: AsyncSession) -> None:
    pro = await buat_toko_siap_pakai(db_session, nama_paket="Pro")
    r = await client.post("/promo", headers=pro.headers, json=_promo(nama="Promo Biasa"))
    assert r.status_code == 201, r.text
    assert r.json()["khusus_ulang_tahun"] is False


async def test_promo_khusus_ulang_tahun_digerbang_paket(client: AsyncClient, db_session: AsyncSession) -> None:
    pro = await buat_toko_siap_pakai(db_session, nama_paket="Pro")  # punya diskon, belum birthday_promo
    r = await client.post("/promo", headers=pro.headers, json=_promo(khusus_ulang_tahun=True))
    assert r.status_code == 403 and r.json()["detail"]["fitur"] == "birthday_promo"

    bisnis = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    ok = await client.post("/promo", headers=bisnis.headers, json=_promo(khusus_ulang_tahun=True))
    assert ok.status_code == 201, ok.text
    assert ok.json()["khusus_ulang_tahun"] is True


async def test_ubah_penanda_ulang_tahun_hanya_digerbang_saat_berubah_jadi_aktif(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    pro = await buat_toko_siap_pakai(db_session, nama_paket="Pro")
    promo = (await client.post("/promo", headers=pro.headers, json=_promo(nama="Biasa"))).json()
    url = f"/promo/{promo['id']}"
    # Klien mengirim ulang seluruh isian: nilai False tidak boleh digerbang
    assert (await client.patch(url, headers=pro.headers, json={"nama": "Biasa 2", "khusus_ulang_tahun": False})).status_code == 200
    r = await client.patch(url, headers=pro.headers, json={"khusus_ulang_tahun": True})
    assert r.status_code == 403 and r.json()["detail"]["fitur"] == "birthday_promo"

    bisnis = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    p2 = (await client.post("/promo", headers=bisnis.headers, json=_promo(khusus_ulang_tahun=True))).json()
    # Sudah aktif: mengirim ulang True tetap lolos; mematikan selalu boleh
    assert (await client.patch(f"/promo/{p2['id']}", headers=bisnis.headers, json={"khusus_ulang_tahun": True, "nilai": 25})).status_code == 200
    off = await client.patch(f"/promo/{p2['id']}", headers=bisnis.headers, json={"khusus_ulang_tahun": False})
    assert off.status_code == 200 and off.json()["khusus_ulang_tahun"] is False


async def test_pelanggan_menyimpan_dan_mengubah_tanggal_lahir(client: AsyncClient, toko_a) -> None:
    r = await client.post(
        "/pelanggan", headers=toko_a.headers, json={"nama": "Sari", "no_hp": "081200000001", "tanggal_lahir": "1995-04-12"}
    )
    assert r.status_code == 201, r.text
    assert r.json()["tanggal_lahir"] == "1995-04-12"
    pid = r.json()["id"]
    ubah = await client.patch(f"/pelanggan/{pid}", headers=toko_a.headers, json={"tanggal_lahir": "1990-12-31"})
    assert ubah.status_code == 200 and ubah.json()["tanggal_lahir"] == "1990-12-31"
    assert (await client.get(f"/pelanggan/{pid}", headers=toko_a.headers)).json()["tanggal_lahir"] == "1990-12-31"
    assert (await client.patch(f"/pelanggan/{pid}", headers=toko_a.headers, json={"tanggal_lahir": "bukan-tanggal"})).status_code == 422


async def test_sync_pull_membawa_tanggal_lahir_dan_penanda_promo(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    perangkat = await buat_perangkat(db_session, toko.toko.id, toko.outlet.id)
    await client.post("/pelanggan", headers=toko.headers, json={"nama": "Sari", "tanggal_lahir": "1995-04-12"})
    await client.post("/promo", headers=toko.headers, json=_promo(khusus_ulang_tahun=True))

    resp = await client.get("/sync/pull", headers=toko.headers, params={"since": EPOCH, "perangkat_id": str(perangkat.id)})
    assert resp.status_code == 200, resp.text
    b = resp.json()
    sari = [p for p in b["pelanggan"] if p["nama"] == "Sari"][0]
    assert sari["tanggal_lahir"] == str(date(1995, 4, 12))
    assert [p["khusus_ulang_tahun"] for p in b["promo"]] == [True]
