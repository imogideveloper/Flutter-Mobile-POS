"""IMOGI no. 82: anggaran bulanan per kategori, realisasi, dan proyeksi akhir bulan."""

from datetime import UTC, date, datetime
from decimal import Decimal

from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.pengeluaran import Pengeluaran
from app.models.produk import Produk
from tests.conftest import buat_metode_bayar, buat_toko_siap_pakai


async def _biaya(db: AsyncSession, toko_id, kategori: str, jumlah: str, tgl: date) -> None:
    db.add(Pengeluaran(toko_id=toko_id, tanggal=tgl, kategori=kategori, jumlah=Decimal(jumlah)))
    await db.commit()


async def test_ringkasan_status_proyeksi_dan_arus_kas(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    tid = toko.toko.id
    await _biaya(db_session, tid, "gas_lpg", "90000", date(2026, 11, 3))  # 90% dari 100.000 -> waspada
    await _biaya(db_session, tid, "sewa", "1200000", date(2026, 11, 5))  # lewat
    await _biaya(db_session, tid, "kemasan", "50000", date(2026, 11, 6))  # tanpa anggaran
    await _biaya(db_session, tid, "gas_lpg", "999", date(2026, 10, 30))  # bulan lain, tidak ikut
    for kategori, jumlah in [("gas_lpg", "100000"), ("sewa", "1000000"), ("pemasaran", "300000")]:
        r = await client.put("/anggaran", headers=toko.headers, json={"bulan": "2026-11", "kategori": kategori, "jumlah": jumlah})
        assert r.status_code == 204, r.text

    produk = Produk(toko_id=tid, nama="Kopi", harga_jual=Decimal("20000"), hpp=Decimal("8000"))
    db_session.add(produk)
    await db_session.commit()
    await db_session.refresh(produk)
    metode = await buat_metode_bayar(db_session, tid)
    trx = await client.post(
        "/transaksi",
        headers=toko.headers,
        json={
            "outlet_id": str(toko.outlet.id),
            "nomor_struk": "AG-1",
            "tanggal": datetime(2026, 11, 2, 9, tzinfo=UTC).isoformat(),
            "items": [{"produk_id": str(produk.id), "nama_produk": "Kopi", "qty": "10", "harga_satuan": "20000", "hpp_satuan": "8000"}],
            "metode_bayar_id": str(metode.id),
            "total_bayar": "200000",
        },
    )
    assert trx.status_code == 201, trx.text

    res = await client.get("/anggaran", headers=toko.headers, params={"bulan": "2026-11", "per": "2026-11-10"})
    assert res.status_code == 200, res.text
    data = res.json()
    assert data["hari_berjalan"] == 10 and data["jumlah_hari"] == 30
    per = {b["kategori"]: b for b in data["baris"]}
    assert per["gas_lpg"]["status"] == "waspada" and Decimal(per["gas_lpg"]["sisa"]) == 10000
    assert Decimal(per["gas_lpg"]["proyeksi"]) == 270000  # 90.000 / 10 hari x 30
    assert per["sewa"]["status"] == "lewat"
    assert per["kemasan"]["status"] == "tanpa_anggaran" and per["kemasan"]["persen"] is None
    assert per["pemasaran"]["status"] == "aman" and Decimal(per["pemasaran"]["realisasi"]) == 0
    assert Decimal(data["total_realisasi"]) == 90000 + 1200000 + 50000
    assert Decimal(data["penjualan_realisasi"]) == 200000
    assert Decimal(data["penjualan_proyeksi"]) == 600000
    assert Decimal(data["arus_kas_proyeksi"]) == 600000 - Decimal(data["total_proyeksi"])


async def test_bulan_lampau_tidak_diproyeksi_dan_anggaran_bisa_diubah(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    await _biaya(db_session, toko.toko.id, "gas_lpg", "50000", date(2026, 9, 10))
    for jumlah in ("100000", "40000"):  # upsert: yang terakhir berlaku
        await client.put("/anggaran", headers=toko.headers, json={"bulan": "2026-09", "kategori": "gas_lpg", "jumlah": jumlah})
    data = (await client.get("/anggaran", headers=toko.headers, params={"bulan": "2026-09", "per": "2026-11-17"})).json()
    baris = data["baris"][0]
    assert data["hari_berjalan"] == 30
    assert Decimal(baris["anggaran"]) == 40000 and baris["status"] == "lewat"
    assert Decimal(baris["proyeksi"]) == Decimal(baris["realisasi"]) == 50000


async def test_validasi_isolasi_dan_paket(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    lain = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    ok = {"bulan": "2026-11", "kategori": "sewa", "jumlah": "500"}
    assert (await client.put("/anggaran", headers=toko.headers, json={**ok, "kategori": "ngawur"})).status_code == 422
    assert (await client.put("/anggaran", headers=toko.headers, json={**ok, "bulan": "2026-13"})).status_code == 422
    assert (await client.put("/anggaran", headers=toko.headers, json={**ok, "jumlah": "-1"})).status_code == 422
    await client.put("/anggaran", headers=toko.headers, json=ok)
    data = (await client.get("/anggaran", headers=lain.headers, params={"bulan": "2026-11"})).json()
    assert data["baris"] == [], "anggaran toko lain tidak terlihat"
    gratis = await buat_toko_siap_pakai(db_session, nama_paket="Gratis")
    assert (await client.get("/anggaran", headers=gratis.headers, params={"bulan": "2026-11"})).status_code == 403


async def test_salin_anggaran_tidak_menimpa_yang_sudah_ada(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    for bulan, kategori, jumlah in [("2026-10", "sewa", "1000"), ("2026-10", "gas_lpg", "200"), ("2026-11", "sewa", "5000")]:
        await client.put("/anggaran", headers=toko.headers, json={"bulan": bulan, "kategori": kategori, "jumlah": jumlah})
    r = await client.post("/anggaran/salin", headers=toko.headers, json={"dari": "2026-10", "ke": "2026-11"})
    assert r.status_code == 201 and r.json()["disalin"] == 1, "hanya gas_lpg yang belum ada"
    per = {
        b["kategori"]: Decimal(b["anggaran"])
        for b in (await client.get("/anggaran", headers=toko.headers, params={"bulan": "2026-11"})).json()["baris"]
    }
    assert per == {"sewa": 5000, "gas_lpg": 200}, "anggaran lama tidak ditimpa"
    assert (await client.post("/anggaran/salin", headers=toko.headers, json={"dari": "2026-11", "ke": "2026-11"})).status_code == 422
    assert (await client.post("/anggaran/salin", headers=toko.headers, json={"dari": "2025-01", "ke": "2026-11"})).status_code == 404
