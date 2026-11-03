from datetime import UTC, datetime
from decimal import Decimal

from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.stok import Stok
from tests.conftest import buat_metode_bayar, buat_produk


async def test_checkout_sukses_menghitung_total_dan_mendebet_stok(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id, harga_jual=Decimal("15000"))
    metode = await buat_metode_bayar(db_session, toko_a.toko.id)

    resp = await client.post(
        "/transaksi",
        headers=toko_a.headers,
        json={
            "outlet_id": str(toko_a.outlet.id),
            "nomor_struk": "OUT1-0001",
            "tanggal": datetime.now(UTC).isoformat(),
            "items": [
                {
                    "produk_id": str(produk.id),
                    "nama_produk": produk.nama,
                    "qty": "2",
                    "harga_satuan": "15000",
                }
            ],
            "metode_bayar_id": str(metode.id),
            "total_bayar": "40000",
        },
    )
    assert resp.status_code == 201
    body = resp.json()
    assert body["subtotal"] == "30000.00"
    assert body["total"] == "30000.00"
    assert body["kembalian"] == "10000.00"

    stok = (
        await db_session.execute(select(Stok).where(Stok.produk_id == produk.id))
    ).scalar_one()
    assert stok.jumlah == Decimal("-2")  # belum ada stok awal - jadi minus (aturan #4.3: boleh minus)


async def test_checkout_dengan_pajak_aktif(client: AsyncClient, db_session: AsyncSession, toko_a) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id, harga_jual=Decimal("15000"))
    metode = await buat_metode_bayar(db_session, toko_a.toko.id)

    await client.post(
        "/pajak", headers=toko_a.headers, json={"nama": "PPN", "persen": "11", "urutan": 0}
    )

    resp = await client.post(
        "/transaksi",
        headers=toko_a.headers,
        json={
            "outlet_id": str(toko_a.outlet.id),
            "nomor_struk": "OUT1-0002",
            "tanggal": datetime.now(UTC).isoformat(),
            "items": [
                {"produk_id": str(produk.id), "nama_produk": produk.nama, "qty": "2", "harga_satuan": "15000"}
            ],
            "metode_bayar_id": str(metode.id),
            "total_bayar": "50000",
        },
    )
    assert resp.status_code == 201
    body = resp.json()
    assert body["subtotal"] == "30000.00"
    assert body["total_pajak"] == "3300.00"
    assert body["total"] == "33300.00"
    assert body["kembalian"] == "16700.00"


async def test_checkout_uang_kurang_ditolak_fitur_kasbon_terkunci(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    # toko_a = paket Gratis (tidak punya fitur 'kasbon') - uang kurang
    # TIDAK lagi 400 generik sejak tahap 3b-1, tapi 403 fitur_terkunci
    # (lihat tests/test_kasbon.py utk perilaku kasbon sungguhan paket Pro+).
    produk = await buat_produk(db_session, toko_a.toko.id, harga_jual=Decimal("15000"))
    metode = await buat_metode_bayar(db_session, toko_a.toko.id)

    resp = await client.post(
        "/transaksi",
        headers=toko_a.headers,
        json={
            "outlet_id": str(toko_a.outlet.id),
            "nomor_struk": "OUT1-0003",
            "tanggal": datetime.now(UTC).isoformat(),
            "items": [
                {"produk_id": str(produk.id), "nama_produk": produk.nama, "qty": "1", "harga_satuan": "15000"}
            ],
            "metode_bayar_id": str(metode.id),
            "total_bayar": "5000",
        },
    )
    assert resp.status_code == 403
    assert resp.json()["detail"]["kode"] == "fitur_terkunci"
    assert resp.json()["detail"]["fitur"] == "kasbon"


async def test_checkout_idempotent_berdasarkan_id(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    import uuid

    produk = await buat_produk(db_session, toko_a.toko.id, harga_jual=Decimal("15000"))
    metode = await buat_metode_bayar(db_session, toko_a.toko.id)
    transaksi_id = str(uuid.uuid4())

    payload = {
        "id": transaksi_id,
        "outlet_id": str(toko_a.outlet.id),
        "nomor_struk": "OUT1-0004",
        "tanggal": datetime.now(UTC).isoformat(),
        "items": [
            {"produk_id": str(produk.id), "nama_produk": produk.nama, "qty": "1", "harga_satuan": "15000"}
        ],
        "metode_bayar_id": str(metode.id),
        "total_bayar": "15000",
    }

    resp1 = await client.post("/transaksi", headers=toko_a.headers, json=payload)
    assert resp1.status_code == 201

    resp2 = await client.post("/transaksi", headers=toko_a.headers, json=payload)
    assert resp2.status_code == 201
    assert resp2.json()["id"] == transaksi_id

    stok = (await db_session.execute(select(Stok).where(Stok.produk_id == produk.id))).scalar_one()
    assert stok.jumlah == Decimal("-1"), "push ulang transaksi yang sama tidak boleh mendebet stok dua kali"


async def test_checkout_split_payment_tunai_dan_kartu(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    import uuid

    from app.models.transaksi import Pembayaran

    produk = await buat_produk(db_session, toko_a.toko.id, harga_jual=Decimal("50000"))
    tunai = await buat_metode_bayar(db_session, toko_a.toko.id, tipe="tunai", masuk_laci=True)
    kartu = await buat_metode_bayar(db_session, toko_a.toko.id, tipe="kartu", masuk_laci=False)

    resp = await client.post(
        "/transaksi",
        headers=toko_a.headers,
        json={
            "outlet_id": str(toko_a.outlet.id),
            "nomor_struk": "OUT1-SPLIT-1",
            "tanggal": datetime.now(UTC).isoformat(),
            "items": [
                {"produk_id": str(produk.id), "nama_produk": produk.nama, "qty": "1", "harga_satuan": "50000"}
            ],
            "metode_bayar_id": str(tunai.id),
            "total_bayar": "50000",
            "split_pembayaran": [
                {"metode_bayar_id": str(tunai.id), "jumlah": "20000"},
                {
                    "metode_bayar_id": str(kartu.id),
                    "jumlah": "30000",
                    "nomor_referensi": "TRX123",
                    "empat_digit_akhir_kartu": "4242",
                },
            ],
        },
    )
    assert resp.status_code == 201
    transaksi_id = uuid.UUID(resp.json()["id"])

    rows = (
        await db_session.execute(select(Pembayaran).where(Pembayaran.transaksi_id == transaksi_id))
    ).scalars().all()
    assert len(rows) == 2
    jumlah_by_metode = {str(r.metode_bayar_id): r.jumlah for r in rows}
    assert jumlah_by_metode[str(tunai.id)] == Decimal("20000.00")
    assert jumlah_by_metode[str(kartu.id)] == Decimal("30000.00")
    kartu_row = next(r for r in rows if r.metode_bayar_id == kartu.id)
    assert kartu_row.ref_gateway == "TRX123"
    assert kartu_row.payload_gateway == {"empat_digit_akhir_kartu": "4242"}


async def test_checkout_split_payment_jumlah_tidak_sama_ditolak(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id, harga_jual=Decimal("50000"))
    tunai = await buat_metode_bayar(db_session, toko_a.toko.id, tipe="tunai", masuk_laci=True)
    kartu = await buat_metode_bayar(db_session, toko_a.toko.id, tipe="kartu", masuk_laci=False)

    resp = await client.post(
        "/transaksi",
        headers=toko_a.headers,
        json={
            "outlet_id": str(toko_a.outlet.id),
            "nomor_struk": "OUT1-SPLIT-2",
            "tanggal": datetime.now(UTC).isoformat(),
            "items": [
                {"produk_id": str(produk.id), "nama_produk": produk.nama, "qty": "1", "harga_satuan": "50000"}
            ],
            "metode_bayar_id": str(tunai.id),
            "total_bayar": "50000",
            "split_pembayaran": [
                {"metode_bayar_id": str(tunai.id), "jumlah": "20000"},
                {"metode_bayar_id": str(kartu.id), "jumlah": "20000"},
            ],
        },
    )
    assert resp.status_code == 400
    assert resp.json()["detail"]["kode"] == "split_pembayaran_tidak_sama"
