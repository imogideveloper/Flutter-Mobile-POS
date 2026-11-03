"""Temuan A.2 (tahap 5) - transaksi.snapshot_struk disimpan APA ADANYA
dari body checkout, dan bisa diambil balik lewat GET /transaksi/{id} -
termasuk dari toko lain (harus 404, bukan bocor)."""

from datetime import UTC, datetime
from decimal import Decimal

from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from tests.conftest import buat_metode_bayar, buat_produk, buat_toko_siap_pakai

_SNAPSHOT = {
    "data": {
        "namaOutlet": "Toko Kopi",
        "nomorStruk": "OUT1-0001",
        "items": [{"namaProduk": "Kopi Hitam", "qty": 1, "hargaSatuan": 15000, "subtotal": 15000}],
        "subtotal": 15000,
        "total": 15000,
    },
    "pengaturan": {"headerStruk": "Terima kasih", "lebarKertasMm": 58},
}


async def test_snapshot_struk_tersimpan_apa_adanya(client: AsyncClient, db_session: AsyncSession, toko_a) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id, harga_jual=Decimal("15000"))
    metode = await buat_metode_bayar(db_session, toko_a.toko.id)

    resp = await client.post(
        "/transaksi",
        headers=toko_a.headers,
        json={
            "outlet_id": str(toko_a.outlet.id),
            "nomor_struk": "SNAP-1",
            "tanggal": datetime.now(UTC).isoformat(),
            "items": [
                {"produk_id": str(produk.id), "nama_produk": produk.nama, "qty": "1", "harga_satuan": "15000"}
            ],
            "metode_bayar_id": str(metode.id),
            "total_bayar": "15000",
            "snapshot_struk": _SNAPSHOT,
        },
    )
    assert resp.status_code == 201, resp.text
    transaksi_id = resp.json()["id"]

    resp_detail = await client.get(f"/transaksi/{transaksi_id}", headers=toko_a.headers)
    assert resp_detail.status_code == 200
    assert resp_detail.json()["snapshot_struk"] == _SNAPSHOT


async def test_snapshot_struk_null_kalau_tidak_dikirim(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id, harga_jual=Decimal("15000"))
    metode = await buat_metode_bayar(db_session, toko_a.toko.id)

    resp = await client.post(
        "/transaksi",
        headers=toko_a.headers,
        json={
            "outlet_id": str(toko_a.outlet.id),
            "nomor_struk": "SNAP-2",
            "tanggal": datetime.now(UTC).isoformat(),
            "items": [
                {"produk_id": str(produk.id), "nama_produk": produk.nama, "qty": "1", "harga_satuan": "15000"}
            ],
            "metode_bayar_id": str(metode.id),
            "total_bayar": "15000",
        },
    )
    assert resp.status_code == 201, resp.text
    resp_detail = await client.get(f"/transaksi/{resp.json()['id']}", headers=toko_a.headers)
    assert resp_detail.json()["snapshot_struk"] is None


async def test_snapshot_struk_toko_lain_ditolak(client: AsyncClient, db_session: AsyncSession) -> None:
    toko_a = await buat_toko_siap_pakai(db_session)
    toko_b = await buat_toko_siap_pakai(db_session)
    produk = await buat_produk(db_session, toko_a.toko.id, harga_jual=Decimal("15000"))
    metode = await buat_metode_bayar(db_session, toko_a.toko.id)

    resp = await client.post(
        "/transaksi",
        headers=toko_a.headers,
        json={
            "outlet_id": str(toko_a.outlet.id),
            "nomor_struk": "SNAP-3",
            "tanggal": datetime.now(UTC).isoformat(),
            "items": [
                {"produk_id": str(produk.id), "nama_produk": produk.nama, "qty": "1", "harga_satuan": "15000"}
            ],
            "metode_bayar_id": str(metode.id),
            "total_bayar": "15000",
            "snapshot_struk": _SNAPSHOT,
        },
    )
    transaksi_id = resp.json()["id"]

    resp_b = await client.get(f"/transaksi/{transaksi_id}", headers=toko_b.headers)
    assert resp_b.status_code == 404
