import uuid
from datetime import UTC, datetime
from decimal import Decimal

from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.order import PesananDapur
from app.models.produk import Kategori, Produk
from tests.conftest import buat_metode_bayar, buat_perangkat, buat_produk, buat_toko_siap_pakai


async def test_tipe_order_crud_dan_isolasi_antar_toko(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    # tipe_order adalah fitur tingkat 1 (Pro) - toko_a/toko_b default
    # Gratis, jadi pakai toko Bisnis lokal di sini (bukan fixture) supaya
    # tes CRUD/isolasi ini tidak tercampur dgn tes gating fitur-nya
    # sendiri (lihat tests/test_gating_fitur.py).
    toko_a = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    toko_b = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")

    resp = await client.post(
        "/tipe-order", headers=toko_a.headers, json={"nama": "Makan di tempat", "kanal": "makan_di_tempat", "pakai_meja": True}
    )
    assert resp.status_code == 201

    daftar_a = await client.get("/tipe-order", headers=toko_a.headers)
    assert len(daftar_a.json()) == 1

    daftar_b = await client.get("/tipe-order", headers=toko_b.headers)
    assert daftar_b.json() == []


async def test_meja_butuh_outlet_milik_toko_sendiri(
    client: AsyncClient, toko_a, toko_b
) -> None:
    resp = await client.post(
        f"/outlets/{toko_a.outlet.id}/meja", headers=toko_a.headers, json={"nama": "A1", "kapasitas": 4}
    )
    assert resp.status_code == 201

    # Toko B coba bikin meja di outlet milik toko A - harus 404.
    resp_b = await client.post(
        f"/outlets/{toko_a.outlet.id}/meja", headers=toko_b.headers, json={"nama": "Nyelonong"}
    )
    assert resp_b.status_code == 404

    daftar = await client.get(f"/outlets/{toko_a.outlet.id}/meja", headers=toko_a.headers)
    assert len(daftar.json()) == 1
    assert daftar.json()[0]["nama"] == "A1"


async def test_stasiun_dapur_crud(client: AsyncClient, toko_a) -> None:
    resp = await client.post(
        f"/outlets/{toko_a.outlet.id}/stasiun-dapur",
        headers=toko_a.headers,
        json={"nama": "Dapur", "lebar_kertas_mm": 58},
    )
    assert resp.status_code == 201

    daftar = await client.get(f"/outlets/{toko_a.outlet.id}/stasiun-dapur", headers=toko_a.headers)
    assert len(daftar.json()) == 1
    assert daftar.json()[0]["nama"] == "Dapur"


async def test_antrean_nomor_bertambah_tiap_dipanggil(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    # nomor_antrean adalah fitur tingkat 2 (Bisnis).
    toko_a = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    perangkat = await buat_perangkat(db_session, toko_a.toko.id, toko_a.outlet.id)

    resp1 = await client.post(
        "/antrean/nomor",
        headers=toko_a.headers,
        params={"outlet_id": str(toko_a.outlet.id), "perangkat_id": str(perangkat.id), "prefix": "A"},
    )
    assert resp1.status_code == 200
    assert resp1.json()["nomor_lengkap"] == "A-001"

    resp2 = await client.post(
        "/antrean/nomor",
        headers=toko_a.headers,
        params={"outlet_id": str(toko_a.outlet.id), "perangkat_id": str(perangkat.id), "prefix": "A"},
    )
    assert resp2.json()["nomor_lengkap"] == "A-002"


async def test_checkout_toko_bisnis_otomatis_bikin_tiket_dapur_per_stasiun(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    metode = await buat_metode_bayar(db_session, toko.toko.id)

    resp_dapur = await client.post(
        f"/outlets/{toko.outlet.id}/stasiun-dapur", headers=toko.headers, json={"nama": "Dapur"}
    )
    stasiun_dapur_id = resp_dapur.json()["id"]
    resp_bar = await client.post(
        f"/outlets/{toko.outlet.id}/stasiun-dapur", headers=toko.headers, json={"nama": "Bar"}
    )
    stasiun_bar_id = resp_bar.json()["id"]

    kategori_makanan = Kategori(
        toko_id=toko.toko.id, nama="Makanan", stasiun_dapur_id=uuid.UUID(stasiun_dapur_id)
    )
    kategori_minuman = Kategori(
        toko_id=toko.toko.id, nama="Minuman", stasiun_dapur_id=uuid.UUID(stasiun_bar_id)
    )
    db_session.add_all([kategori_makanan, kategori_minuman])
    await db_session.flush()

    nasi = Produk(toko_id=toko.toko.id, kategori_id=kategori_makanan.id, nama="Nasi Goreng", harga_jual=Decimal("25000"))
    es_teh = Produk(toko_id=toko.toko.id, kategori_id=kategori_minuman.id, nama="Es Teh", harga_jual=Decimal("8000"))
    db_session.add_all([nasi, es_teh])
    await db_session.commit()
    await db_session.refresh(nasi)
    await db_session.refresh(es_teh)

    resp = await client.post(
        "/transaksi",
        headers=toko.headers,
        json={
            "outlet_id": str(toko.outlet.id),
            "nomor_struk": "OUT1-D001",
            "tanggal": datetime.now(UTC).isoformat(),
            "items": [
                {"produk_id": str(nasi.id), "nama_produk": nasi.nama, "qty": "1", "harga_satuan": "25000"},
                {"produk_id": str(es_teh.id), "nama_produk": es_teh.nama, "qty": "2", "harga_satuan": "8000"},
            ],
            "metode_bayar_id": str(metode.id),
            "total_bayar": "41000",
        },
    )
    assert resp.status_code == 201
    transaksi_id = resp.json()["id"]

    tiket_rows = (
        await db_session.execute(select(PesananDapur).where(PesananDapur.transaksi_id == uuid.UUID(transaksi_id)))
    ).scalars().all()
    assert len(tiket_rows) == 2
    stasiun_di_tiket = {str(t.stasiun_dapur_id) for t in tiket_rows}
    assert stasiun_di_tiket == {stasiun_dapur_id, stasiun_bar_id}

    resp_list = await client.get(
        "/dapur/pesanan", headers=toko.headers, params={"outlet_id": str(toko.outlet.id)}
    )
    assert resp_list.status_code == 200
    assert len(resp_list.json()) == 2
    for tiket in resp_list.json():
        assert tiket["status"] == "baru"

    tiket_dapur_id = next(t["id"] for t in resp_list.json() if t["stasiun_dapur_id"] == stasiun_dapur_id)
    resp_ubah = await client.patch(
        f"/dapur/pesanan/{tiket_dapur_id}/status", headers=toko.headers, json={"status": "siap"}
    )
    assert resp_ubah.status_code == 200
    assert resp_ubah.json()["status"] == "siap"
    assert resp_ubah.json()["siap_pada"] is not None


async def test_checkout_toko_gratis_tidak_bikin_tiket_dapur(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id)
    metode = await buat_metode_bayar(db_session, toko_a.toko.id)

    resp = await client.post(
        "/transaksi",
        headers=toko_a.headers,
        json={
            "outlet_id": str(toko_a.outlet.id),
            "nomor_struk": "OUT1-D010",
            "tanggal": datetime.now(UTC).isoformat(),
            "items": [
                {"produk_id": str(produk.id), "nama_produk": produk.nama, "qty": "1", "harga_satuan": "15000"}
            ],
            "metode_bayar_id": str(metode.id),
            "total_bayar": "15000",
        },
    )
    assert resp.status_code == 201
    transaksi_id = resp.json()["id"]

    tiket_rows = (
        await db_session.execute(select(PesananDapur).where(PesananDapur.transaksi_id == uuid.UUID(transaksi_id)))
    ).scalars().all()
    assert tiket_rows == []


async def _buat_tiket_dapur(client: AsyncClient, db_session: AsyncSession):
    """Toko Bisnis + 1 tiket dapur sungguhan (lewat checkout nyata, bukan
    insert manual) - dipakai tes isolasi di bawah. Return (toko, pesanan_id)."""

    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    metode = await buat_metode_bayar(db_session, toko.toko.id)

    resp_dapur = await client.post(
        f"/outlets/{toko.outlet.id}/stasiun-dapur", headers=toko.headers, json={"nama": "Dapur"}
    )
    stasiun_dapur_id = resp_dapur.json()["id"]

    kategori = Kategori(toko_id=toko.toko.id, nama="Makanan", stasiun_dapur_id=uuid.UUID(stasiun_dapur_id))
    db_session.add(kategori)
    await db_session.flush()
    nasi = Produk(toko_id=toko.toko.id, kategori_id=kategori.id, nama="Nasi Goreng", harga_jual=Decimal("25000"))
    db_session.add(nasi)
    await db_session.commit()
    await db_session.refresh(nasi)

    resp = await client.post(
        "/transaksi",
        headers=toko.headers,
        json={
            "outlet_id": str(toko.outlet.id),
            "nomor_struk": "OUT1-ISO-DAPUR",
            "tanggal": datetime.now(UTC).isoformat(),
            "items": [{"produk_id": str(nasi.id), "nama_produk": nasi.nama, "qty": "1", "harga_satuan": "25000"}],
            "metode_bayar_id": str(metode.id),
            "total_bayar": "25000",
        },
    )
    assert resp.status_code == 201
    transaksi_id = resp.json()["id"]

    tiket = (
        await db_session.execute(select(PesananDapur).where(PesananDapur.transaksi_id == uuid.UUID(transaksi_id)))
    ).scalars().one()
    return toko, tiket.id


async def test_ubah_status_pesanan_dapur_tolak_toko_lain(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    """Sebelumnya dikecualikan dari sweep sweep tahap 1 (setup terlalu
    kompleks utk sweep generik) - dites manual di sini: toko B tidak
    boleh mengubah status tiket dapur milik toko A."""

    toko_a, pesanan_id = await _buat_tiket_dapur(client, db_session)
    toko_b = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")

    resp = await client.patch(
        f"/dapur/pesanan/{pesanan_id}/status", headers=toko_b.headers, json={"status": "siap"}
    )
    assert resp.status_code == 404

    tiket = await db_session.get(PesananDapur, pesanan_id)
    assert tiket.status == "baru"  # tidak tersentuh


async def test_ubah_status_pesanan_dapur_oleh_pemilik_toko_berhasil(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    toko_a, pesanan_id = await _buat_tiket_dapur(client, db_session)

    resp = await client.patch(
        f"/dapur/pesanan/{pesanan_id}/status", headers=toko_a.headers, json={"status": "siap"}
    )
    assert resp.status_code == 200
    assert resp.json()["status"] == "siap"
