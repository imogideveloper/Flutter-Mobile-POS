"""IMOGI no. 27: order diterima dulu, dibayar belakangan. Bukan kasbon: tanpa
pelanggan, tanpa fitur kasbon (paket Gratis boleh), tanpa jatuh tempo."""

import uuid
from datetime import UTC, datetime
from decimal import Decimal

from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.transaksi import Transaksi
from tests.conftest import buat_metode_bayar, buat_produk, buat_toko_siap_pakai


async def _siapkan(client: AsyncClient, db: AsyncSession, nama_paket: str = "Gratis"):
    toko = await buat_toko_siap_pakai(db, nama_paket=nama_paket)
    produk = await buat_produk(db, toko.toko.id, harga_jual=Decimal("25000"))
    metode = await buat_metode_bayar(db, toko.toko.id)
    resp = await client.post(
        "/shift/buka", headers=toko.headers, json={"outlet_id": str(toko.outlet.id), "modal_awal": "0"}
    )
    assert resp.status_code == 201
    return toko, produk, metode, resp.json()["id"]


def _body(toko, produk, metode, shift_id, **tambahan) -> dict:
    return {
        "outlet_id": str(toko.outlet.id),
        "shift_id": shift_id,
        "nomor_struk": f"BB-{uuid.uuid4().hex[:6]}",
        "tanggal": datetime.now(UTC).isoformat(),
        "items": [{"produk_id": str(produk.id), "nama_produk": produk.nama, "qty": "2", "harga_satuan": "25000"}],
        "metode_bayar_id": str(metode.id),
        "total_bayar": "0",
        **tambahan,
    }


async def test_order_bayar_belakangan_diterima_tanpa_pelanggan_di_paket_gratis(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    toko, produk, metode, shift_id = await _siapkan(client, db_session)

    resp = await client.post(
        "/transaksi", headers=toko.headers, json=_body(toko, produk, metode, shift_id, bayar_belakangan=True)
    )
    assert resp.status_code == 201, resp.text
    data = resp.json()
    assert data["status_bayar"] == "belum_bayar"
    assert data["sisa_tagihan"] == "50000.00"

    baris = (await db_session.execute(select(Transaksi).where(Transaksi.id == uuid.UUID(data["id"])))).scalar_one()
    assert baris.bayar_belakangan is True
    assert baris.pelanggan_id is None
    assert baris.jatuh_tempo is None, "order bayar belakangan tidak punya jatuh tempo utang"


async def test_tanpa_penanda_total_bayar_nol_tetap_kasbon_dan_butuh_pelanggan(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    toko, produk, metode, shift_id = await _siapkan(client, db_session, "Pro")
    resp = await client.post("/transaksi", headers=toko.headers, json=_body(toko, produk, metode, shift_id))
    assert resp.status_code == 400
    assert resp.json()["detail"]["kode"] == "kasbon_butuh_pelanggan"


async def test_bayar_belakangan_dengan_uang_masuk_ditolak(client: AsyncClient, db_session: AsyncSession) -> None:
    toko, produk, metode, shift_id = await _siapkan(client, db_session)
    resp = await client.post(
        "/transaksi",
        headers=toko.headers,
        json=_body(toko, produk, metode, shift_id, bayar_belakangan=True, total_bayar="10000"),
    )
    assert resp.status_code == 422
    assert resp.json()["detail"]["kode"] == "bayar_belakangan_harus_nol"


async def test_order_dilunasi_belakangan_lewat_endpoint_pembayaran(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    toko, produk, metode, shift_id = await _siapkan(client, db_session)
    dibuat = await client.post(
        "/transaksi", headers=toko.headers, json=_body(toko, produk, metode, shift_id, bayar_belakangan=True)
    )
    transaksi_id = dibuat.json()["id"]

    bayar = await client.post(
        f"/transaksi/{transaksi_id}/pembayaran",
        headers=toko.headers,
        json={"shift_id": shift_id, "metode_bayar_id": str(metode.id), "jumlah": "50000"},
    )
    assert bayar.status_code == 201, bayar.text
    assert bayar.json()["jenis"] == "pelunasan"
    assert bayar.json()["status_bayar"] == "lunas"
    assert bayar.json()["sisa_tagihan"] == "0.00"


async def test_push_offline_order_bayar_belakangan_diterima(client: AsyncClient, db_session: AsyncSession) -> None:
    """Push offline membawa id dari HP; order belum dibayar tanpa pelanggan tidak boleh membuat push ditolak."""
    toko, produk, metode, shift_id = await _siapkan(client, db_session)
    id_hp = str(uuid.uuid4())
    body = _body(toko, produk, metode, shift_id, bayar_belakangan=True, id=id_hp)
    resp = await client.post("/transaksi", headers=toko.headers, json=body)
    assert resp.status_code == 201, resp.text
    assert resp.json()["id"] == id_hp
    assert resp.json()["status_bayar"] == "belum_bayar"
