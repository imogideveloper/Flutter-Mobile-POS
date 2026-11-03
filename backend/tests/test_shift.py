from datetime import UTC, datetime
from decimal import Decimal

from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from tests.conftest import buat_metode_bayar, buat_produk


async def test_buka_shift_lalu_tutup_dengan_selisih_nol(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    resp_buka = await client.post(
        "/shift/buka",
        headers=toko_a.headers,
        json={"outlet_id": str(toko_a.outlet.id), "modal_awal": "50000"},
    )
    assert resp_buka.status_code == 201
    shift_id = resp_buka.json()["id"]
    assert resp_buka.json()["status"] == "buka"

    resp_tutup = await client.post(
        f"/shift/{shift_id}/tutup", headers=toko_a.headers, json={"kas_aktual": "50000"}
    )
    assert resp_tutup.status_code == 200
    body = resp_tutup.json()
    assert body["kas_seharusnya"] == "50000.00"
    assert body["selisih"] == "0.00"
    assert body["status"] == "tutup"


async def test_kas_seharusnya_menghitung_tunai_dari_penjualan_dan_kas_manual(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id, harga_jual=Decimal("15000"))
    tunai = await buat_metode_bayar(db_session, toko_a.toko.id, tipe="tunai")
    qris = await buat_metode_bayar(db_session, toko_a.toko.id, tipe="qris", masuk_laci=False)

    resp_buka = await client.post(
        "/shift/buka",
        headers=toko_a.headers,
        json={"outlet_id": str(toko_a.outlet.id), "modal_awal": "100000"},
    )
    shift_id = resp_buka.json()["id"]

    # Penjualan tunai 30.000 - masuk laci, ikut dihitung.
    await client.post(
        "/transaksi",
        headers=toko_a.headers,
        json={
            "outlet_id": str(toko_a.outlet.id),
            "shift_id": shift_id,
            "nomor_struk": "OUT1-S001",
            "tanggal": datetime.now(UTC).isoformat(),
            "items": [
                {"produk_id": str(produk.id), "nama_produk": produk.nama, "qty": "2", "harga_satuan": "15000"}
            ],
            "metode_bayar_id": str(tunai.id),
            "total_bayar": "30000",
        },
    )
    # Penjualan QRIS 15.000 - TIDAK masuk laci, tidak boleh ikut dihitung.
    await client.post(
        "/transaksi",
        headers=toko_a.headers,
        json={
            "outlet_id": str(toko_a.outlet.id),
            "shift_id": shift_id,
            "nomor_struk": "OUT1-S002",
            "tanggal": datetime.now(UTC).isoformat(),
            "items": [
                {"produk_id": str(produk.id), "nama_produk": produk.nama, "qty": "1", "harga_satuan": "15000"}
            ],
            "metode_bayar_id": str(qris.id),
            "total_bayar": "15000",
        },
    )

    await client.post(
        f"/shift/{shift_id}/kas",
        headers=toko_a.headers,
        json={"jenis": "keluar", "jumlah": "20000", "keterangan": "Beli galon"},
    )

    # kas_seharusnya = 100.000 modal + 30.000 tunai - 20.000 keluar = 110.000
    resp_tutup = await client.post(
        f"/shift/{shift_id}/tutup", headers=toko_a.headers, json={"kas_aktual": "105000"}
    )
    assert resp_tutup.status_code == 200
    body = resp_tutup.json()
    assert body["kas_seharusnya"] == "110000.00"
    assert body["selisih"] == "-5000.00"


async def test_kas_seharusnya_split_payment_hanya_hitung_baris_tunai(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    """F3.A - split payment satu transaksi tunai+kartu: cuma porsi tunainya
    yang boleh menambah kas_seharusnya, porsi kartu tidak."""
    produk = await buat_produk(db_session, toko_a.toko.id, harga_jual=Decimal("50000"))
    tunai = await buat_metode_bayar(db_session, toko_a.toko.id, tipe="tunai")
    kartu = await buat_metode_bayar(db_session, toko_a.toko.id, tipe="kartu", masuk_laci=False)

    resp_buka = await client.post(
        "/shift/buka",
        headers=toko_a.headers,
        json={"outlet_id": str(toko_a.outlet.id), "modal_awal": "0"},
    )
    shift_id = resp_buka.json()["id"]

    await client.post(
        "/transaksi",
        headers=toko_a.headers,
        json={
            "outlet_id": str(toko_a.outlet.id),
            "shift_id": shift_id,
            "nomor_struk": "OUT1-SPLIT-SHIFT",
            "tanggal": datetime.now(UTC).isoformat(),
            "items": [
                {"produk_id": str(produk.id), "nama_produk": produk.nama, "qty": "1", "harga_satuan": "50000"}
            ],
            "metode_bayar_id": str(tunai.id),
            "total_bayar": "50000",
            "split_pembayaran": [
                {"metode_bayar_id": str(tunai.id), "jumlah": "20000"},
                {"metode_bayar_id": str(kartu.id), "jumlah": "30000"},
            ],
        },
    )

    resp_tutup = await client.post(
        f"/shift/{shift_id}/tutup", headers=toko_a.headers, json={"kas_aktual": "20000"}
    )
    assert resp_tutup.status_code == 200
    assert resp_tutup.json()["kas_seharusnya"] == "20000.00"


async def test_tidak_bisa_buka_dua_shift_sekaligus_di_outlet_sama(
    client: AsyncClient, toko_a
) -> None:
    await client.post(
        "/shift/buka", headers=toko_a.headers, json={"outlet_id": str(toko_a.outlet.id)}
    )
    resp2 = await client.post(
        "/shift/buka", headers=toko_a.headers, json={"outlet_id": str(toko_a.outlet.id)}
    )
    assert resp2.status_code == 409
