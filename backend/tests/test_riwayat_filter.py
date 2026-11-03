"""F3.B - filter rentang tanggal + pagination di GET /transaksi, dipakai
RiwayatListPage saat perlu data lebih lama drpd yang tersimpan lokal."""

from datetime import UTC, datetime, timedelta
from decimal import Decimal

from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from tests.conftest import buat_metode_bayar, buat_produk


async def _checkout(client, toko_a, produk, metode, nomor_struk, tanggal):
    return await client.post(
        "/transaksi",
        headers=toko_a.headers,
        json={
            "outlet_id": str(toko_a.outlet.id),
            "nomor_struk": nomor_struk,
            "tanggal": tanggal.isoformat(),
            "items": [
                {"produk_id": str(produk.id), "nama_produk": produk.nama, "qty": "1", "harga_satuan": "15000"}
            ],
            "metode_bayar_id": str(metode.id),
            "total_bayar": "15000",
        },
    )


async def test_daftar_transaksi_filter_rentang_tanggal(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id, harga_jual=Decimal("15000"))
    metode = await buat_metode_bayar(db_session, toko_a.toko.id)

    sekarang = datetime.now(UTC)
    lama = sekarang - timedelta(days=10)
    await _checkout(client, toko_a, produk, metode, "OUT1-LAMA", lama)
    await _checkout(client, toko_a, produk, metode, "OUT1-BARU", sekarang)

    resp_semua = await client.get("/transaksi", headers=toko_a.headers)
    assert resp_semua.status_code == 200
    assert len(resp_semua.json()["items"]) == 2

    resp_filter = await client.get(
        "/transaksi",
        headers=toko_a.headers,
        params={"dari_tanggal": (sekarang - timedelta(days=1)).isoformat()},
    )
    assert resp_filter.status_code == 200
    body = resp_filter.json()
    assert len(body["items"]) == 1
    assert body["items"][0]["nomor_struk"] == "OUT1-BARU"
    assert body["has_more"] is False


async def test_daftar_transaksi_pagination_has_more(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id, harga_jual=Decimal("15000"))
    metode = await buat_metode_bayar(db_session, toko_a.toko.id)
    sekarang = datetime.now(UTC)

    for i in range(3):
        await _checkout(
            client, toko_a, produk, metode, f"OUT1-PAGE-{i}", sekarang - timedelta(minutes=i)
        )

    resp = await client.get("/transaksi", headers=toko_a.headers, params={"limit": 2})
    assert resp.status_code == 200
    body = resp.json()
    assert len(body["items"]) == 2
    assert body["has_more"] is True

    resp_offset = await client.get(
        "/transaksi", headers=toko_a.headers, params={"limit": 2, "offset": 2}
    )
    assert resp_offset.status_code == 200
    body_offset = resp_offset.json()
    assert len(body_offset["items"]) == 1
    assert body_offset["has_more"] is False
