"""IMOGI no. 43: jual per kemasan. Stok tetap di satuan dasar; baris transaksi dalam satuan kemasan."""

import uuid
from datetime import UTC, datetime
from decimal import Decimal

from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.stok import Stok
from app.models.transaksi import ItemTransaksi
from tests.conftest import buat_metode_bayar, buat_produk, buat_toko_siap_pakai


async def test_tambah_kemasan_ditolak_untuk_paket_gratis(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session)
    produk = await buat_produk(db_session, toko.toko.id)
    resp = await client.post(
        f"/produk/{produk.id}/kemasan", headers=toko.headers, json={"nama": "Dus", "isi": 12, "harga": 150000}
    )
    assert resp.status_code == 403
    assert "fitur_terkunci" in resp.text


async def test_crud_kemasan_validasi_dan_nama_unik(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    produk = await buat_produk(db_session, toko.toko.id)
    url = f"/produk/{produk.id}/kemasan"

    resp = await client.post(url, headers=toko.headers, json={"nama": "Dus", "isi": 12, "harga": 150000})
    assert resp.status_code == 201, resp.text
    dus = resp.json()
    assert float(dus["isi"]) == 12 and float(dus["harga"]) == 150000

    assert (await client.post(url, headers=toko.headers, json={"nama": "Dus", "isi": 6, "harga": 1})).status_code == 409
    assert (await client.post(url, headers=toko.headers, json={"nama": "Pak", "isi": 1, "harga": 1})).status_code == 422
    assert (await client.post(url, headers=toko.headers, json={"nama": "  ", "isi": 6, "harga": 1})).status_code == 422

    resp = await client.patch(f"/kemasan/{dus['id']}", headers=toko.headers, json={"harga": 140000})
    assert resp.status_code == 200 and float(resp.json()["harga"]) == 140000

    await client.post(url, headers=toko.headers, json={"nama": "Pak", "isi": 4, "harga": 50000})
    daftar = (await client.get(url, headers=toko.headers)).json()
    assert [k["nama"] for k in daftar] == ["Pak", "Dus"], "urut dari isi terkecil"

    assert (await client.delete(f"/kemasan/{dus['id']}", headers=toko.headers)).status_code == 204
    daftar = (await client.get(url, headers=toko.headers)).json()
    assert [k["nama"] for k in daftar] == ["Pak"]


async def test_kemasan_toko_lain_ditolak_dan_ikut_sync_pull(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    lain = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    produk = await buat_produk(db_session, toko.toko.id)
    dus = (
        await client.post(
            f"/produk/{produk.id}/kemasan", headers=toko.headers, json={"nama": "Dus", "isi": 12, "harga": 150000}
        )
    ).json()

    assert (await client.get(f"/produk/{produk.id}/kemasan", headers=lain.headers)).status_code == 404
    assert (await client.patch(f"/kemasan/{dus['id']}", headers=lain.headers, json={"harga": 1})).status_code == 404
    assert (await client.delete(f"/kemasan/{dus['id']}", headers=lain.headers)).status_code == 404

    from tests.conftest import buat_perangkat

    perangkat = await buat_perangkat(db_session, toko.toko.id, toko.outlet.id)
    resp = await client.get(
        "/sync/pull",
        headers=toko.headers,
        params={"since": "1970-01-01T00:00:00Z", "perangkat_id": str(perangkat.id), "outlet_id": str(toko.outlet.id)},
    )
    assert resp.status_code == 200, resp.text
    kemasan = resp.json()["produk_kemasan"]
    assert [k["id"] for k in kemasan] == [dus["id"]]
    assert kemasan[0]["nama"] == "Dus"


def _body_push(toko, produk, metode, **item_lebih) -> dict:
    return {
        "id": str(uuid.uuid4()),
        "outlet_id": str(toko.outlet.id),
        "nomor_struk": f"OUT1-K{uuid.uuid4().hex[:6]}",
        "tanggal": datetime.now(UTC).isoformat(),
        "items": [
            {
                "produk_id": str(produk.id),
                "nama_produk": produk.nama,
                "qty": "2",
                "harga_satuan": "150000",
                "hpp_satuan": "120000",
                "isi_kemasan": "12",
                "nama_kemasan": "Dus",
                **item_lebih,
            }
        ],
        "metode_bayar_id": str(metode.id),
        "total_bayar": "300000",
        "subtotal_klien": "300000",
        "total_klien": "300000",
    }


async def _stok(db: AsyncSession, produk_id) -> Decimal:
    db.expire_all()
    return (await db.execute(select(Stok).where(Stok.produk_id == produk_id))).scalar_one().jumlah


async def test_push_kemasan_potong_stok_sebesar_qty_kali_isi_dan_void_mengembalikan(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    produk = await buat_produk(db_session, toko.toko.id, harga_jual=Decimal("15000"))
    metode = await buat_metode_bayar(db_session, toko.toko.id)
    produk_id = produk.id

    body = _body_push(toko, produk, metode)
    resp = await client.post("/transaksi", headers=toko.headers, json=body)
    assert resp.status_code == 201, resp.text
    assert resp.json()["total"] == "300000.00", "uang dihitung per kemasan: 2 dus x 150000"

    assert await _stok(db_session, produk_id) == Decimal("-24"), "2 dus x isi 12 = 24 satuan dasar"
    item = (await db_session.execute(select(ItemTransaksi))).scalars().one()
    assert item.nama_kemasan == "Dus" and Decimal(str(item.isi_kemasan)) == 12
    assert Decimal(str(item.qty)) == 2 and Decimal(str(item.harga_satuan)) == 150000

    resp = await client.post(f"/transaksi/{body['id']}/void", headers=toko.headers, json={"alasan": "Salah"})
    assert resp.status_code == 200, resp.text
    assert await _stok(db_session, produk_id) == Decimal("0"), "void mengembalikan 24 satuan dasar"


async def test_checkout_online_menolak_kemasan(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    produk = await buat_produk(db_session, toko.toko.id)
    metode = await buat_metode_bayar(db_session, toko.toko.id)
    body = _body_push(toko, produk, metode)
    del body["id"]  # tanpa id = checkout online

    resp = await client.post("/transaksi", headers=toko.headers, json=body)
    assert resp.status_code == 422
    assert "kemasan" in resp.text


async def test_item_biasa_tetap_isi_satu_dan_nama_kemasan_dibuang(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    produk = await buat_produk(db_session, toko.toko.id, harga_jual=Decimal("15000"))
    produk_id = produk.id
    metode = await buat_metode_bayar(db_session, toko.toko.id)
    body = _body_push(
        toko, produk, metode, qty="2", harga_satuan="15000", hpp_satuan="0", isi_kemasan="1", nama_kemasan="Dus"
    )
    body.update({"total_bayar": "30000", "subtotal_klien": "30000", "total_klien": "30000"})

    resp = await client.post("/transaksi", headers=toko.headers, json=body)
    assert resp.status_code == 201, resp.text
    item = (await db_session.execute(select(ItemTransaksi))).scalars().one()
    assert item.nama_kemasan is None and Decimal(str(item.isi_kemasan)) == 1
    assert await _stok(db_session, produk_id) == Decimal("-2")


async def test_refund_sebagian_kemasan_mengembalikan_stok_sebesar_qty_kali_isi(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    produk = await buat_produk(db_session, toko.toko.id, harga_jual=Decimal("15000"))
    produk_id = produk.id
    metode = await buat_metode_bayar(db_session, toko.toko.id)
    body = _body_push(toko, produk, metode)
    assert (await client.post("/transaksi", headers=toko.headers, json=body)).status_code == 201
    item_id = str((await db_session.execute(select(ItemTransaksi))).scalars().one().id)
    assert await _stok(db_session, produk_id) == Decimal("-24")

    resp = await client.post(
        f"/transaksi/{body['id']}/refund",
        headers=toko.headers,
        json={"alasan": "1 dus rusak", "items": [{"item_transaksi_id": item_id, "qty": "1"}]},
    )
    assert resp.status_code == 201, resp.text
    assert resp.json()["total"] == "150000.00", "uang refund per kemasan"
    assert await _stok(db_session, produk_id) == Decimal("-12"), "1 dus x isi 12 kembali ke stok"
