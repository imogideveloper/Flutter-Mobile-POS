from datetime import UTC, datetime, timedelta
from decimal import Decimal

from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.produk import Produk
from tests.conftest import buat_metode_bayar, buat_toko_siap_pakai


async def _produk_dengan_hpp(db: AsyncSession, toko_id, *, harga: str, hpp: str) -> Produk:
    produk = Produk(toko_id=toko_id, nama="Kopi Susu", harga_jual=Decimal(harga), hpp=Decimal(hpp))
    db.add(produk)
    await db.commit()
    await db.refresh(produk)
    return produk


async def _jual(client: AsyncClient, toko, produk, metode, *, qty: str, nomor: str, tanggal: datetime) -> None:
    resp = await client.post(
        "/transaksi",
        headers=toko.headers,
        json={
            "outlet_id": str(toko.outlet.id),
            "nomor_struk": nomor,
            "tanggal": tanggal.isoformat(),
            "items": [
                {
                    "produk_id": str(produk.id),
                    "nama_produk": produk.nama,
                    "qty": qty,
                    "harga_satuan": str(produk.harga_jual),
                    "hpp_satuan": str(produk.hpp),
                }
            ],
            "metode_bayar_id": str(metode.id),
            "total_bayar": str(Decimal(qty) * produk.harga_jual),
        },
    )
    assert resp.status_code == 201, resp.text


def _rentang(sekarang: datetime) -> dict:
    return {
        "dari": (sekarang - timedelta(days=1)).isoformat(),
        "sampai": (sekarang + timedelta(days=1)).isoformat(),
    }


async def test_laba_rugi_menghitung_hpp_biaya_operasional_dan_laba_bersih(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    produk = await _produk_dengan_hpp(db_session, toko.toko.id, harga="15000", hpp="6000")
    metode = await buat_metode_bayar(db_session, toko.toko.id)
    sekarang = datetime.now(UTC)
    await _jual(client, toko, produk, metode, qty="2", nomor="OUT1-LR1", tanggal=sekarang)

    tgl = sekarang.date().isoformat()
    for kategori, jumlah in (("gas_lpg", 5000), ("sewa", 3000), ("belanja_bahan", 10000)):
        r = await client.post(
            "/pengeluaran", headers=toko.headers, json={"tanggal": tgl, "kategori": kategori, "jumlah": jumlah}
        )
        assert r.status_code == 201, r.text

    resp = await client.get("/laporan/laba-rugi", headers=toko.headers, params=_rentang(sekarang))
    assert resp.status_code == 200, resp.text
    b = resp.json()
    assert Decimal(b["penjualan_kotor"]) == Decimal("30000")
    assert Decimal(b["penjualan_bersih"]) == Decimal("30000")
    assert Decimal(b["hpp"]) == Decimal("12000")
    assert Decimal(b["laba_kotor"]) == Decimal("18000")
    # Belanja bahan tidak dikurangkan lagi (sudah di HPP); hanya gas dan sewa.
    assert Decimal(b["total_biaya_operasional"]) == Decimal("8000")
    assert {k["kategori"] for k in b["biaya_operasional"]} == {"gas_lpg", "sewa"}
    assert Decimal(b["belanja_bahan"]) == Decimal("10000")
    assert Decimal(b["laba_bersih"]) == Decimal("10000")
    assert b["jumlah_transaksi"] == 1


async def test_laba_rugi_pengeluaran_di_luar_rentang_tidak_ikut(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    sekarang = datetime.now(UTC)
    lama = (sekarang - timedelta(days=10)).date().isoformat()
    await client.post("/pengeluaran", headers=toko.headers, json={"tanggal": lama, "kategori": "sewa", "jumlah": 99000})

    b = (await client.get("/laporan/laba-rugi", headers=toko.headers, params=_rentang(sekarang))).json()
    assert Decimal(b["total_biaya_operasional"]) == 0
    assert Decimal(b["laba_bersih"]) == 0
    assert b["jumlah_transaksi"] == 0


async def test_laba_rugi_digate_paket_izin_dan_rentang(client: AsyncClient, db_session: AsyncSession) -> None:
    sekarang = datetime.now(UTC)
    gratis = await buat_toko_siap_pakai(db_session, nama_paket="Gratis")
    r = await client.get("/laporan/laba-rugi", headers=gratis.headers, params=_rentang(sekarang))
    assert r.status_code == 403 and r.json()["detail"]["fitur"] == "profit_loss"

    pro = await buat_toko_siap_pakai(db_session, nama_paket="Pro")
    r = await client.get("/laporan/laba-rugi", headers=pro.headers, params=_rentang(sekarang))
    assert r.status_code == 403 and r.json()["detail"]["fitur"] == "profit_loss"

    kasir = await buat_toko_siap_pakai(db_session, nama_role="Kasir", nama_paket="Bisnis")
    r = await client.get("/laporan/laba-rugi", headers=kasir.headers, params=_rentang(sekarang))
    assert r.status_code == 403

    bisnis = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    terbalik = {"dari": sekarang.isoformat(), "sampai": (sekarang - timedelta(days=1)).isoformat()}
    assert (await client.get("/laporan/laba-rugi", headers=bisnis.headers, params=terbalik)).status_code == 400


async def test_laba_rugi_terisolasi_antar_toko(client: AsyncClient, db_session: AsyncSession) -> None:
    a = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    b = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    sekarang = datetime.now(UTC)
    await client.post(
        "/pengeluaran", headers=a.headers, json={"tanggal": sekarang.date().isoformat(), "kategori": "sewa", "jumlah": 7000}
    )
    hasil_b = (await client.get("/laporan/laba-rugi", headers=b.headers, params=_rentang(sekarang))).json()
    assert Decimal(hasil_b["total_biaya_operasional"]) == 0
    # outlet milik toko lain ditolak
    r = await client.get(
        "/laporan/laba-rugi", headers=b.headers, params={**_rentang(sekarang), "outlet_id": str(a.outlet.id)}
    )
    assert r.status_code in (403, 404)
