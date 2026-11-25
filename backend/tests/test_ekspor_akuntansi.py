"""IMOGI no. 85: ekspor ringkasan harian (CSV netral) untuk software akuntansi."""

import csv
import io
import uuid
from datetime import UTC, date, datetime
from decimal import Decimal
from types import SimpleNamespace

from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.pengeluaran import Pengeluaran
from app.models.produk import Produk
from app.routers.ekspor_akuntansi import KOLOM, ke_csv, susun_baris
from tests.conftest import buat_metode_bayar, buat_toko_siap_pakai


def test_susun_baris_menjumlah_per_tanggal_jenis_rincian_dan_terurut() -> None:
    t1 = SimpleNamespace(id=uuid.uuid4(), tanggal=datetime(2026, 11, 2, 9, tzinfo=UTC), subtotal=100, total_diskon=10, total_pajak=5)
    t2 = SimpleNamespace(id=uuid.uuid4(), tanggal=datetime(2026, 11, 2, 15, tzinfo=UTC), subtotal=50, total_diskon=0, total_pajak=0)
    baris = susun_baris(
        [t1, t2],
        {t1.id: Decimal("40"), t2.id: Decimal("20")},
        [(date(2026, 11, 2), "QRIS", Decimal("100")), (date(2026, 11, 2), "QRIS", Decimal("50"))],
        [(date(2026, 11, 1), "sewa", Decimal("700"))],
    )
    assert baris[0] == ("2026-11-01", "biaya", "sewa", Decimal("700")), "tanggal terawal dulu"
    kamus = {(b[0], b[1], b[2]): b[3] for b in baris}
    assert kamus[("2026-11-02", "penjualan_bersih", "")] == Decimal("140")
    assert kamus[("2026-11-02", "hpp", "")] == Decimal("60")
    assert kamus[("2026-11-02", "penerimaan", "QRIS")] == Decimal("150")


def test_ke_csv_memakai_header_tetap_dan_dua_desimal() -> None:
    isi = ke_csv([("2026-11-02", "biaya", "gas, lpg", Decimal("12.5"))])
    baris = list(csv.reader(io.StringIO(isi)))
    assert tuple(baris[0]) == KOLOM
    assert baris[1] == ["2026-11-02", "biaya", "gas, lpg", "12.50", "", ""], "koma di rincian di-quote; kategori tak dikenal tanpa akun"


async def test_endpoint_ekspor_end_to_end(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    produk = Produk(toko_id=toko.toko.id, nama="Kopi", harga_jual=Decimal("20000"), hpp=Decimal("8000"))
    db_session.add(produk)
    db_session.add(Pengeluaran(toko_id=toko.toko.id, tanggal=datetime.now(UTC).date(), kategori="sewa", jumlah=Decimal("1000")))
    await db_session.commit()
    await db_session.refresh(produk)
    metode = await buat_metode_bayar(db_session, toko.toko.id, tipe="qris")
    r = await client.post(
        "/transaksi",
        headers=toko.headers,
        json={
            "outlet_id": str(toko.outlet.id),
            "nomor_struk": "EK-1",
            "tanggal": datetime.now(UTC).isoformat(),
            "items": [{"produk_id": str(produk.id), "nama_produk": "Kopi", "qty": "2", "harga_satuan": "20000", "hpp_satuan": "8000"}],
            "metode_bayar_id": str(metode.id),
            "total_bayar": "40000",
        },
    )
    assert r.status_code == 201, r.text
    hari = str(datetime.now(UTC).date())
    res = await client.get("/ekspor-akuntansi", headers=toko.headers, params={"dari": hari, "sampai": hari})
    assert res.status_code == 200, res.text
    data = res.json()
    baris = {(b[1], b[2]): b[3] for b in csv.reader(io.StringIO(data["csv"])) if b[0] == hari}
    assert Decimal(baris[("penjualan_bersih", "")]) == 40000
    assert Decimal(baris[("hpp", "")]) == 16000
    assert Decimal(baris[("penerimaan", "Qris")]) == 40000
    assert Decimal(baris[("biaya", "sewa")]) == 1000
    assert data["nama_berkas"] == f"akuntansi_{hari}_{hari}.csv"
    assert data["jumlah_baris"] == len(list(csv.reader(io.StringIO(data["csv"])))) - 1


async def test_validasi_isolasi_dan_paket(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    lain = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    p = {"dari": "2026-11-10", "sampai": "2026-11-01"}
    assert (await client.get("/ekspor-akuntansi", headers=toko.headers, params=p)).status_code == 422
    p = {"dari": "2026-01-01", "sampai": "2026-12-31"}
    assert (await client.get("/ekspor-akuntansi", headers=toko.headers, params=p)).status_code == 422
    db_session.add(Pengeluaran(toko_id=toko.toko.id, tanggal=date(2026, 11, 3), kategori="sewa", jumlah=Decimal("5")))
    await db_session.commit()
    p = {"dari": "2026-11-01", "sampai": "2026-11-30"}
    assert (await client.get("/ekspor-akuntansi", headers=lain.headers, params=p)).json()["jumlah_baris"] == 0
    gratis = await buat_toko_siap_pakai(db_session, nama_paket="Gratis")
    assert (await client.get("/ekspor-akuntansi", headers=gratis.headers, params=p)).status_code == 403
