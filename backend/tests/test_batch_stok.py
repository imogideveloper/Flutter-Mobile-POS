"""IMOGI no. 50: batch stok dan pengingat kedaluwarsa (digate paket, izin stok.kelola, ikut sync pull)."""

from datetime import UTC, datetime

from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from tests.conftest import buat_produk, buat_toko_siap_pakai


def _body(toko, produk, **lebih) -> dict:
    return {
        "outlet_id": str(toko.outlet.id),
        "produk_id": str(produk.id),
        "nomor_batch": "B-001",
        "tanggal_kedaluwarsa": "2026-12-31",
        "qty": 12,
        **lebih,
    }


async def test_tambah_batch_ditolak_untuk_paket_gratis(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session)
    produk = await buat_produk(db_session, toko.toko.id)
    resp = await client.post("/stok/batch", headers=toko.headers, json=_body(toko, produk))
    assert resp.status_code == 403
    assert "fitur_terkunci" in resp.text


async def test_tambah_daftar_dan_hapus_batch(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    produk = await buat_produk(db_session, toko.toko.id)

    await client.post("/stok/batch", headers=toko.headers, json=_body(toko, produk, tanggal_kedaluwarsa="2027-02-01"))
    resp = await client.post("/stok/batch", headers=toko.headers, json=_body(toko, produk, nomor_batch=" "))
    assert resp.status_code == 201, resp.text
    baru = resp.json()
    assert baru["nomor_batch"] is None, "nomor batch kosong disimpan null"
    assert float(baru["qty_awal"]) == 12 and float(baru["qty_sisa"]) == 12 and baru["ingatkan_hari"] == 30

    daftar = (await client.get("/stok/batch", headers=toko.headers, params={"outlet_id": str(toko.outlet.id)})).json()
    assert [b["tanggal_kedaluwarsa"] for b in daftar] == ["2026-12-31", "2027-02-01"], "urut dari yang paling dekat"

    assert (await client.delete(f"/stok/batch/{baru['id']}", headers=toko.headers)).status_code == 204
    daftar = (await client.get("/stok/batch", headers=toko.headers, params={"outlet_id": str(toko.outlet.id)})).json()
    assert len(daftar) == 1
    assert (await client.delete(f"/stok/batch/{baru['id']}", headers=toko.headers)).status_code == 404


async def test_batch_validasi_dan_isolasi_toko(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    lain = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    produk = await buat_produk(db_session, toko.toko.id)
    produk_lain = await buat_produk(db_session, lain.toko.id)

    assert (await client.post("/stok/batch", headers=toko.headers, json=_body(toko, produk, qty=0))).status_code == 422
    # produk toko lain ditolak, begitu juga outlet toko lain
    assert (await client.post("/stok/batch", headers=toko.headers, json=_body(toko, produk_lain))).status_code == 404
    assert (
        await client.post("/stok/batch", headers=toko.headers, json=_body(lain, produk))
    ).status_code == 404
    batch = (await client.post("/stok/batch", headers=toko.headers, json=_body(toko, produk))).json()
    assert (await client.delete(f"/stok/batch/{batch['id']}", headers=lain.headers)).status_code == 404
    daftar_lain = await client.get("/stok/batch", headers=lain.headers, params={"outlet_id": str(toko.outlet.id)})
    assert daftar_lain.status_code == 404


async def test_kasir_tanpa_izin_stok_ditolak(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_role="Kasir", nama_paket="Bisnis")
    produk = await buat_produk(db_session, toko.toko.id)
    assert (await client.post("/stok/batch", headers=toko.headers, json=_body(toko, produk))).status_code == 403


async def test_batch_ikut_sync_pull_beserta_penghapusan(client: AsyncClient, db_session: AsyncSession) -> None:
    from app.models.outlet import Perangkat

    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    produk = await buat_produk(db_session, toko.toko.id)
    perangkat = Perangkat(
        toko_id=toko.toko.id, outlet_id=toko.outlet.id, nama="HP", device_uid="dev-batch", platform="android"
    )
    db_session.add(perangkat)
    await db_session.commit()

    batch = (await client.post("/stok/batch", headers=toko.headers, json=_body(toko, produk))).json()
    params = {
        "since": datetime(1970, 1, 1, tzinfo=UTC).isoformat(),
        "perangkat_id": str(perangkat.id),
        "outlet_id": str(toko.outlet.id),
    }
    hasil = (await client.get("/sync/pull", headers=toko.headers, params=params)).json()
    assert [b["id"] for b in hasil["batch_stok"]] == [batch["id"]]
    assert hasil["batch_stok"][0]["tanggal_kedaluwarsa"] == "2026-12-31"
    assert hasil["batch_stok"][0]["deleted_at"] is None

    await client.delete(f"/stok/batch/{batch['id']}", headers=toko.headers)
    hasil = (await client.get("/sync/pull", headers=toko.headers, params=params)).json()
    assert hasil["batch_stok"][0]["deleted_at"] is not None
