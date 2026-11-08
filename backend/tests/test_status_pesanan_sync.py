"""Status pesanan (alur IMOGI) lewat sync: status awal ikut payload checkout, dan
perubahan sesudah tersync dikirim lewat daftar `status_pesanan`."""

import uuid
from datetime import UTC, datetime

import pytest
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.transaksi import Transaksi
from tests.conftest import buat_metode_bayar, buat_perangkat, buat_produk


def _transaksi(outlet_id, produk, metode, transaksi_id: str, **tambahan) -> dict:
    return {
        "id": transaksi_id,
        "outlet_id": str(outlet_id),
        "nomor_struk": f"OUT1-ST-{transaksi_id[:6]}",
        "tanggal": datetime.now(UTC).isoformat(),
        "items": [{"produk_id": str(produk.id), "nama_produk": produk.nama, "qty": "1", "harga_satuan": "15000"}],
        "metode_bayar_id": str(metode.id),
        "total_bayar": "15000",
        **tambahan,
    }


async def _siapkan(db_session: AsyncSession, toko):
    produk = await buat_produk(db_session, toko.toko.id)
    metode = await buat_metode_bayar(db_session, toko.toko.id)
    perangkat = await buat_perangkat(db_session, toko.toko.id, toko.outlet.id)
    return produk, metode, perangkat


async def _status(db_session: AsyncSession, transaksi_id: str) -> str | None:
    db_session.expire_all()
    row = (await db_session.execute(select(Transaksi).where(Transaksi.id == uuid.UUID(transaksi_id)))).scalar_one()
    return row.status_pesanan


async def test_status_awal_ikut_payload_checkout(client: AsyncClient, db_session: AsyncSession, toko_a) -> None:
    produk, metode, perangkat = await _siapkan(db_session, toko_a)
    tid = str(uuid.uuid4())
    resp = await client.post(
        "/sync/push",
        headers=toko_a.headers,
        json={
            "perangkat_id": str(perangkat.id),
            "transaksi": [_transaksi(toko_a.outlet.id, produk, metode, tid, status_pesanan="baru")],
        },
    )
    assert resp.status_code == 200
    assert resp.json()["transaksi"][0]["status"] == "diterima"
    assert await _status(db_session, tid) == "baru"


async def test_tanpa_status_awal_tetap_diterima(client: AsyncClient, db_session: AsyncSession, toko_a) -> None:
    produk, metode, perangkat = await _siapkan(db_session, toko_a)
    tid = str(uuid.uuid4())
    resp = await client.post(
        "/sync/push",
        headers=toko_a.headers,
        json={"perangkat_id": str(perangkat.id), "transaksi": [_transaksi(toko_a.outlet.id, produk, metode, tid)]},
    )
    assert resp.status_code == 200
    assert await _status(db_session, tid) is None


async def test_perubahan_status_setelah_tersync_diterapkan(client: AsyncClient, db_session: AsyncSession, toko_a) -> None:
    produk, metode, perangkat = await _siapkan(db_session, toko_a)
    tid = str(uuid.uuid4())
    base = {"perangkat_id": str(perangkat.id)}
    await client.post(
        "/sync/push",
        headers=toko_a.headers,
        json={**base, "transaksi": [_transaksi(toko_a.outlet.id, produk, metode, tid, status_pesanan="baru")]},
    )

    resp = await client.post(
        "/sync/push",
        headers=toko_a.headers,
        json={**base, "status_pesanan": [{"id": tid, "status": "diproses"}]},
    )
    assert resp.status_code == 200
    assert resp.json()["status_pesanan"] == [{"id": tid, "status": "diterima", "pesan": None}]
    assert await _status(db_session, tid) == "diproses"

    for tahap in ("siap", "diantar", "selesai"):
        await client.post(
            "/sync/push", headers=toko_a.headers, json={**base, "status_pesanan": [{"id": tid, "status": tahap}]}
        )
        assert await _status(db_session, tid) == tahap


async def test_status_untuk_transaksi_yang_tidak_ada_ditolak(client: AsyncClient, db_session: AsyncSession, toko_a) -> None:
    _, _, perangkat = await _siapkan(db_session, toko_a)
    resp = await client.post(
        "/sync/push",
        headers=toko_a.headers,
        json={"perangkat_id": str(perangkat.id), "status_pesanan": [{"id": str(uuid.uuid4()), "status": "siap"}]},
    )
    assert resp.status_code == 200
    hasil = resp.json()["status_pesanan"][0]
    assert hasil["status"] == "ditolak"
    assert "tidak ditemukan" in hasil["pesan"]


async def test_status_transaksi_toko_lain_tidak_bisa_diubah(
    client: AsyncClient, db_session: AsyncSession, toko_a, toko_b
) -> None:
    produk, metode, perangkat_a = await _siapkan(db_session, toko_a)
    tid = str(uuid.uuid4())
    await client.post(
        "/sync/push",
        headers=toko_a.headers,
        json={
            "perangkat_id": str(perangkat_a.id),
            "transaksi": [_transaksi(toko_a.outlet.id, produk, metode, tid, status_pesanan="baru")],
        },
    )

    perangkat_b = await buat_perangkat(db_session, toko_b.toko.id, toko_b.outlet.id, device_uid="device-b")
    resp = await client.post(
        "/sync/push",
        headers=toko_b.headers,
        json={"perangkat_id": str(perangkat_b.id), "status_pesanan": [{"id": tid, "status": "selesai"}]},
    )
    assert resp.status_code == 200
    assert resp.json()["status_pesanan"][0]["status"] == "ditolak"
    assert await _status(db_session, tid) == "baru", "status transaksi toko lain tidak boleh berubah"


@pytest.mark.parametrize("nilai", ["hangus", "BARU", ""])
async def test_status_tidak_dikenal_ditolak(client: AsyncClient, db_session: AsyncSession, toko_a, nilai: str) -> None:
    produk, metode, perangkat = await _siapkan(db_session, toko_a)
    resp = await client.post(
        "/sync/push",
        headers=toko_a.headers,
        json={
            "perangkat_id": str(perangkat.id),
            "transaksi": [_transaksi(toko_a.outlet.id, produk, metode, str(uuid.uuid4()), status_pesanan=nilai)],
        },
    )
    assert resp.status_code == 422
