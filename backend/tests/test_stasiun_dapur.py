"""IMOGI no. 35: stasiun dapur (Bar/Dapur) - CRUD, kategori ditautkan ke stasiun (digate paket), ikut sync pull."""

from datetime import UTC, datetime

from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.outlet import Perangkat
from tests.conftest import buat_toko_siap_pakai


async def _stasiun(client: AsyncClient, toko, nama: str = "Bar") -> dict:
    resp = await client.post(f"/outlets/{toko.outlet.id}/stasiun-dapur", headers=toko.headers, json={"nama": nama})
    assert resp.status_code == 201, resp.text
    return resp.json()


async def test_ubah_dan_hapus_stasiun_melepas_kategori(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    bar = await _stasiun(client, toko)

    resp = await client.patch(
        f"/stasiun-dapur/{bar['id']}", headers=toko.headers, json={"nama": "  Bar Kopi ", "lebar_kertas_mm": 80}
    )
    assert resp.status_code == 200, resp.text
    assert resp.json()["nama"] == "Bar Kopi" and resp.json()["lebar_kertas_mm"] == 80
    assert (await client.patch(f"/stasiun-dapur/{bar['id']}", headers=toko.headers, json={"lebar_kertas_mm": 70})).status_code == 400
    assert (await client.patch(f"/stasiun-dapur/{bar['id']}", headers=toko.headers, json={"nama": " "})).status_code == 400

    kat = await client.post("/kategori", headers=toko.headers, json={"nama": "Kopi", "stasiun_dapur_id": bar["id"]})
    assert kat.status_code == 201, kat.text
    assert kat.json()["stasiun_dapur_id"] == bar["id"]

    assert (await client.delete(f"/stasiun-dapur/{bar['id']}", headers=toko.headers)).status_code == 204
    daftar = (await client.get(f"/outlets/{toko.outlet.id}/stasiun-dapur", headers=toko.headers)).json()
    assert daftar == []
    kategori = (await client.get("/kategori", headers=toko.headers)).json()
    assert kategori[0]["stasiun_dapur_id"] is None, "kategori dilepas dari stasiun yang dihapus"
    assert (await client.delete(f"/stasiun-dapur/{bar['id']}", headers=toko.headers)).status_code == 404


async def test_tautan_kategori_ke_stasiun_digate_paket_dan_isolasi_toko(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    gratis = await buat_toko_siap_pakai(db_session)
    bisnis = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    stasiun_gratis = await _stasiun(client, gratis)
    stasiun_bisnis = await _stasiun(client, bisnis)

    kat = (await client.post("/kategori", headers=gratis.headers, json={"nama": "Kopi"})).json()
    resp = await client.patch(f"/kategori/{kat['id']}", headers=gratis.headers, json={"stasiun_dapur_id": stasiun_gratis["id"]})
    assert resp.status_code == 403 and "fitur_terkunci" in resp.text
    # Mengirim ulang kategori tanpa mengubah stasiun tetap boleh (klien mengirim seluruh field).
    assert (await client.patch(f"/kategori/{kat['id']}", headers=gratis.headers, json={"nama": "Kopi 2", "stasiun_dapur_id": None})).status_code == 200

    # Stasiun toko lain ditolak.
    kat_b = (await client.post("/kategori", headers=bisnis.headers, json={"nama": "Teh"})).json()
    resp = await client.patch(f"/kategori/{kat_b['id']}", headers=bisnis.headers, json={"stasiun_dapur_id": stasiun_gratis["id"]})
    assert resp.status_code == 404
    resp = await client.patch(f"/kategori/{kat_b['id']}", headers=bisnis.headers, json={"stasiun_dapur_id": stasiun_bisnis["id"]})
    assert resp.status_code == 200 and resp.json()["stasiun_dapur_id"] == stasiun_bisnis["id"]

    assert (await client.patch(f"/stasiun-dapur/{stasiun_gratis['id']}", headers=bisnis.headers, json={"nama": "X"})).status_code == 404
    assert (await client.delete(f"/stasiun-dapur/{stasiun_gratis['id']}", headers=bisnis.headers)).status_code == 404


async def test_stasiun_dan_tautan_kategori_ikut_sync_pull(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    perangkat = Perangkat(
        toko_id=toko.toko.id, outlet_id=toko.outlet.id, nama="HP", device_uid="dev-stasiun", platform="android"
    )
    db_session.add(perangkat)
    await db_session.commit()
    bar = await _stasiun(client, toko)
    await client.post("/kategori", headers=toko.headers, json={"nama": "Kopi", "stasiun_dapur_id": bar["id"]})

    params = {
        "since": datetime(1970, 1, 1, tzinfo=UTC).isoformat(),
        "perangkat_id": str(perangkat.id),
        "outlet_id": str(toko.outlet.id),
    }
    hasil = (await client.get("/sync/pull", headers=toko.headers, params=params)).json()
    assert [s["nama"] for s in hasil["stasiun_dapur"]] == ["Bar"]
    assert hasil["kategori"][0]["stasiun_dapur_id"] == bar["id"]

    await client.delete(f"/stasiun-dapur/{bar['id']}", headers=toko.headers)
    hasil = (await client.get("/sync/pull", headers=toko.headers, params=params)).json()
    assert hasil["stasiun_dapur"][0]["deleted_at"] is not None
    assert hasil["kategori"][0]["stasiun_dapur_id"] is None
