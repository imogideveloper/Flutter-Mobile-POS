from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from tests.conftest import buat_toko_siap_pakai


async def test_daftar_fitur_publik(client: AsyncClient, toko_a) -> None:
    resp = await client.get("/fitur", headers=toko_a.headers)
    assert resp.status_code == 200
    kode = {f["kode"] for f in resp.json()}
    assert {"pos", "qris", "diskon", "tiket_dapur"}.issubset(kode)


async def test_toko_gratis_hanya_dapat_fitur_tingkat_0(client: AsyncClient, toko_a) -> None:
    resp = await client.get("/fitur/toko", headers=toko_a.headers)
    assert resp.status_code == 200
    body = resp.json()
    assert body["paket"] == "Gratis"
    assert "pos" in body["kode_fitur"]
    assert "laporan_dasar" in body["kode_fitur"]
    assert "qris" not in body["kode_fitur"]
    assert "diskon" not in body["kode_fitur"]
    assert "tiket_dapur" not in body["kode_fitur"]


async def test_toko_pro_dapat_fitur_tingkat_0_dan_1_tapi_bukan_2(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    toko_pro = await buat_toko_siap_pakai(db_session, nama_paket="Pro")

    resp = await client.get("/fitur/toko", headers=toko_pro.headers)
    body = resp.json()
    assert body["paket"] == "Pro"
    assert "pos" in body["kode_fitur"]  # tingkat 0 tetap ikut
    assert "qris" in body["kode_fitur"]
    assert "diskon" in body["kode_fitur"]
    assert "tiket_dapur" not in body["kode_fitur"]  # tingkat 2, bukan Pro
    assert "harga_grosir" not in body["kode_fitur"]


async def test_toko_bisnis_dapat_semua_tingkat(client: AsyncClient, db_session: AsyncSession) -> None:
    toko_bisnis = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")

    resp = await client.get("/fitur/toko", headers=toko_bisnis.headers)
    body = resp.json()
    assert body["paket"] == "Bisnis"
    assert "tiket_dapur" in body["kode_fitur"]
    assert "harga_grosir" in body["kode_fitur"]


async def test_toko_gratis_ditolak_bikin_promo_butuh_upgrade(client: AsyncClient, toko_a) -> None:
    resp = await client.post(
        "/promo",
        headers=toko_a.headers,
        json={"nama": "Diskon Lebaran", "tipe": "persen", "nilai": "10"},
    )
    assert resp.status_code == 403
    detail = resp.json()["detail"]
    assert detail == {"kode": "fitur_terkunci", "fitur": "diskon", "paket_minimal": "Pro"}


async def test_toko_pro_bisa_bikin_promo(client: AsyncClient, db_session: AsyncSession) -> None:
    toko_pro = await buat_toko_siap_pakai(db_session, nama_paket="Pro")

    resp = await client.post(
        "/promo",
        headers=toko_pro.headers,
        json={"nama": "Diskon Lebaran", "tipe": "persen", "nilai": "10"},
    )
    assert resp.status_code == 201


async def test_registrasi_toko_baru_otomatis_dapat_paket_gratis(
    client: AsyncClient, otp_store
) -> None:
    await otp_store.simpan("081355556666", "999999", 300)

    resp = await client.post(
        "/auth/otp/verify",
        json={
            "no_hp": "081355556666",
            "kode": "999999",
            "device_uid": "device-fitur-1",
            "nama_perangkat": "HP Baru",
            "nama_toko": "Warung Baru",
            "nama_pemilik": "Dewi",
        },
    )
    assert resp.status_code == 200
    token = resp.json()["access_token"]

    resp_fitur = await client.get("/fitur/toko", headers={"Authorization": f"Bearer {token}"})
    assert resp_fitur.status_code == 200
    assert resp_fitur.json()["paket"] == "Gratis"
