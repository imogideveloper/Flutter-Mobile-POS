"""Kategori punya penanda masuk tiket dapur atau tidak (IMOGI no. 35)."""

from httpx import AsyncClient

from tests.conftest import buat_perangkat


async def test_kategori_masuk_tiket_dapur_bawaan_dan_bisa_diubah(client: AsyncClient, toko_a) -> None:
    resp = await client.post("/kategori", headers=toko_a.headers, json={"nama": "Makanan"})
    assert resp.status_code == 201
    assert resp.json()["masuk_tiket_dapur"] is True

    resp2 = await client.post(
        "/kategori", headers=toko_a.headers, json={"nama": "Minuman dingin", "masuk_tiket_dapur": False}
    )
    assert resp2.json()["masuk_tiket_dapur"] is False

    patch = await client.patch(
        f"/kategori/{resp.json()['id']}", headers=toko_a.headers, json={"masuk_tiket_dapur": False}
    )
    assert patch.status_code == 200 and patch.json()["masuk_tiket_dapur"] is False


async def test_pull_membawa_penanda_tiket_dapur(client: AsyncClient, db_session, toko_a) -> None:
    perangkat = await buat_perangkat(db_session, toko_a.toko.id, toko_a.outlet.id)
    await client.post("/kategori", headers=toko_a.headers, json={"nama": "Air", "masuk_tiket_dapur": False})
    resp = await client.get(
        "/sync/pull",
        headers=toko_a.headers,
        params={"since": "1970-01-01T00:00:00+00:00", "perangkat_id": str(perangkat.id)},
    )
    assert resp.status_code == 200
    kategori = {k["nama"]: k for k in resp.json()["kategori"]}
    assert kategori["Air"]["masuk_tiket_dapur"] is False
