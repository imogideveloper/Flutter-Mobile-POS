"""IMOGI no. 81 (arahan lead 2026-11-25: laporan keuangan sederhana standar UMKM)."""

from datetime import UTC, date, datetime
from decimal import Decimal

from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.aset_tetap import AsetTetap
from app.models.deposit import DepositPelanggan
from app.models.pelanggan import Pelanggan
from app.models.pengeluaran import Pengeluaran
from app.models.produk import Produk
from tests.conftest import buat_metode_bayar, buat_toko_siap_pakai


async def test_laba_rugi_arus_kas_dan_neraca_seimbang(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    hari = datetime.now(UTC).date()
    produk = Produk(toko_id=toko.toko.id, nama="Kopi", harga_jual=Decimal("20000"), hpp=Decimal("8000"))
    pel = Pelanggan(toko_id=toko.toko.id, nama="Budi")
    db_session.add_all([produk, pel])
    await db_session.flush()
    db_session.add_all([
        Pengeluaran(toko_id=toko.toko.id, tanggal=hari, kategori="sewa", jumlah=Decimal("5000")),
        Pengeluaran(toko_id=toko.toko.id, tanggal=hari, kategori="kemasan", jumlah=Decimal("1000")),
        AsetTetap(toko_id=toko.toko.id, nama="Mesin kopi", tanggal_perolehan=hari.replace(day=1),
                  harga_perolehan=Decimal("1200000"), nilai_residu=Decimal("0"), umur_bulan=12),
        DepositPelanggan(toko_id=toko.toko.id, pelanggan_id=pel.id, jenis="topup", jumlah=Decimal("50000")),
    ])
    await db_session.commit()
    metode = await buat_metode_bayar(db_session, toko.toko.id, tipe="tunai")
    r = await client.post(
        "/transaksi",
        headers=toko.headers,
        json={
            "outlet_id": str(toko.outlet.id),
            "nomor_struk": "LK-1",
            "tanggal": datetime.now(UTC).isoformat(),
            "items": [{"produk_id": str(produk.id), "nama_produk": "Kopi", "qty": "2", "harga_satuan": "20000", "hpp_satuan": "8000"}],
            "metode_bayar_id": str(metode.id),
            "total_bayar": "40000",
        },
    )
    assert r.status_code == 201, r.text

    res = await client.get("/laporan-keuangan", headers=toko.headers, params={"dari": str(hari.replace(day=1)), "sampai": str(hari)})
    assert res.status_code == 200, res.text
    d = res.json()
    lr = d["laba_rugi"]
    akun = {b["kode_akun"]: Decimal(b["jumlah"]) for b in lr["pendapatan"] + lr["hpp"] + lr["beban"]}
    assert akun["4-1000"] == 40000
    assert akun["5-1000"] == 16000
    assert akun["5-1100"] == 1000, "kemasan masuk HPP kemasan"
    assert akun["6-1100"] == 5000, "sewa ke beban sewa"
    assert akun["6-1600"] == 100000, "penyusutan satu bulan mesin kopi"
    assert Decimal(lr["laba_bersih"]) == 40000 - 16000 - 1000 - 5000 - 100000

    ak = d["arus_kas"]
    # Masuk: penjualan 40.000 + deposit 50.000. Keluar: sewa 5.000 + kemasan 1.000 + aset 1.200.000.
    assert Decimal(ak["total_masuk"]) == 90000
    assert Decimal(ak["total_keluar"]) == 1206000

    pos = d["posisi"]
    aset = {b["kode_akun"]: Decimal(b["jumlah"]) for b in pos["aset"]}
    kew = {b["kode_akun"]: Decimal(b["jumlah"]) for b in pos["kewajiban"]}
    assert aset["1-1100"] == 90000 - 1206000, "kas = akumulasi arus kas tercatat"
    assert aset["1-2100"] == 1200000 and aset["1-2200"] == -100000
    assert kew["2-1300"] == 50000, "saldo deposit pelanggan"
    assert Decimal(pos["ekuitas"]) == Decimal(pos["total_aset"]) - Decimal(pos["total_kewajiban"])


async def test_validasi_izin_dan_paket(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    p = {"dari": "2026-11-10", "sampai": "2026-11-01"}
    assert (await client.get("/laporan-keuangan", headers=toko.headers, params=p)).status_code == 422
    p = {"dari": "2026-11-01", "sampai": "2026-11-30"}
    gratis = await buat_toko_siap_pakai(db_session, nama_paket="Gratis")
    assert (await client.get("/laporan-keuangan", headers=gratis.headers, params=p)).status_code == 403
    kasir = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis", nama_role="Kasir")
    assert (await client.get("/laporan-keuangan", headers=kasir.headers, params=p)).status_code == 403
