from datetime import UTC, datetime, timedelta
from decimal import Decimal

from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from tests.conftest import buat_metode_bayar, buat_produk


async def _checkout(
    client: AsyncClient, toko_a, produk, metode, *, qty: str, nomor_struk: str, tanggal: datetime, shift_id: str | None = None
) -> None:
    harga_satuan = produk.harga_jual
    total_bayar = Decimal(qty) * harga_satuan
    payload = {
        "outlet_id": str(toko_a.outlet.id),
        "nomor_struk": nomor_struk,
        "tanggal": tanggal.isoformat(),
        "items": [
            {
                "produk_id": str(produk.id),
                "nama_produk": produk.nama,
                "qty": qty,
                "harga_satuan": str(harga_satuan),
            }
        ],
        "metode_bayar_id": str(metode.id),
        "total_bayar": str(total_bayar),
    }
    if shift_id:
        payload["shift_id"] = shift_id
    resp = await client.post("/transaksi", headers=toko_a.headers, json=payload)
    assert resp.status_code == 201


async def test_laporan_penjualan_menghitung_penjualan_laba_dan_rata_rata(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id, harga_jual=Decimal("15000"))
    metode = await buat_metode_bayar(db_session, toko_a.toko.id)
    sekarang = datetime.now(UTC)

    await _checkout(client, toko_a, produk, metode, qty="2", nomor_struk="OUT1-L001", tanggal=sekarang)
    await _checkout(client, toko_a, produk, metode, qty="1", nomor_struk="OUT1-L002", tanggal=sekarang)

    resp = await client.get(
        "/laporan/penjualan",
        headers=toko_a.headers,
        params={
            "dari": (sekarang - timedelta(days=1)).isoformat(),
            "sampai": (sekarang + timedelta(days=1)).isoformat(),
        },
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["penjualan_bersih"] == "45000.00"
    assert body["jumlah_transaksi"] == 2
    assert body["rata_rata"] == "22500.00"
    # hpp default 0 saat produk dibuat tanpa hpp - laba kotor = penjualan.
    assert body["laba_kotor"] == "45000.000000"
    assert len(body["jam_ramai"]) == 1  # kedua transaksi di jam yg sama
    assert body["metode_bayar"][0]["persen"] == "100"


async def test_laporan_penjualan_rentang_tanggal_di_luar_tidak_ikut(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id)
    metode = await buat_metode_bayar(db_session, toko_a.toko.id)
    kemarin = datetime.now(UTC) - timedelta(days=5)

    await _checkout(client, toko_a, produk, metode, qty="1", nomor_struk="OUT1-L010", tanggal=kemarin)

    resp = await client.get(
        "/laporan/penjualan",
        headers=toko_a.headers,
        params={
            "dari": (datetime.now(UTC) - timedelta(hours=1)).isoformat(),
            "sampai": (datetime.now(UTC) + timedelta(hours=1)).isoformat(),
        },
    )
    assert resp.json()["jumlah_transaksi"] == 0


async def test_produk_terlaris_urut_dari_total_tertinggi(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    kopi = await buat_produk(db_session, toko_a.toko.id, nama="Kopi Hitam", harga_jual=Decimal("15000"))
    roti = await buat_produk(db_session, toko_a.toko.id, nama="Roti Bakar", harga_jual=Decimal("50000"))
    metode = await buat_metode_bayar(db_session, toko_a.toko.id)
    sekarang = datetime.now(UTC)

    await _checkout(client, toko_a, kopi, metode, qty="2", nomor_struk="OUT1-L020", tanggal=sekarang)
    await _checkout(client, toko_a, roti, metode, qty="1", nomor_struk="OUT1-L021", tanggal=sekarang)

    resp = await client.get(
        "/laporan/produk-terlaris",
        headers=toko_a.headers,
        params={
            "dari": (sekarang - timedelta(hours=1)).isoformat(),
            "sampai": (sekarang + timedelta(hours=1)).isoformat(),
        },
    )
    assert resp.status_code == 200
    body = resp.json()
    # Roti 1x50.000 = 50.000 > Kopi 2x15.000 = 30.000 - harus di urutan pertama.
    assert body[0]["nama_produk"] == "Roti Bakar"
    assert Decimal(body[0]["total"]) == Decimal("50000")


async def test_laporan_shift_sedang_berjalan_menghitung_proyeksi_kas(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id, harga_jual=Decimal("15000"))
    tunai = await buat_metode_bayar(db_session, toko_a.toko.id, tipe="tunai")

    resp_buka = await client.post(
        "/shift/buka", headers=toko_a.headers, json={"outlet_id": str(toko_a.outlet.id), "modal_awal": "50000"}
    )
    shift_id = resp_buka.json()["id"]

    await _checkout(
        client, toko_a, produk, tunai, qty="2", nomor_struk="OUT1-L030", tanggal=datetime.now(UTC), shift_id=shift_id
    )

    resp = await client.get(f"/laporan/shift/{shift_id}", headers=toko_a.headers)
    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "buka"
    assert body["jumlah_transaksi"] == 1
    assert body["penjualan_bersih"] == "30000.00"
    assert body["kas_seharusnya"] == "80000.00"  # 50.000 modal + 30.000 tunai (proyeksi, shift masih buka)


async def test_laporan_toko_b_tidak_melihat_data_toko_a(
    client: AsyncClient, db_session: AsyncSession, toko_a, toko_b
) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id)
    metode = await buat_metode_bayar(db_session, toko_a.toko.id)
    sekarang = datetime.now(UTC)
    await _checkout(client, toko_a, produk, metode, qty="1", nomor_struk="OUT1-L040", tanggal=sekarang)

    resp = await client.get(
        "/laporan/penjualan",
        headers=toko_b.headers,
        params={
            "dari": (sekarang - timedelta(hours=1)).isoformat(),
            "sampai": (sekarang + timedelta(hours=1)).isoformat(),
        },
    )
    assert resp.json()["jumlah_transaksi"] == 0
