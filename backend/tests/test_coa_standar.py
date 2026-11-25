"""IMOGI no. 80 tahap 1 (keputusan lead MoM 2026-11-25): bagan akun standar dan pemetaan beban."""

import csv
import io

from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.pengeluaran import KATEGORI_PENGELUARAN
from app.routers.ekspor_akuntansi import ke_csv
from app.services.coa_standar import AKUN_KATEGORI_PENGELUARAN, AKUN_PER_KODE, AKUN_STANDAR, akun_untuk_baris_ekspor
from tests.conftest import buat_toko_siap_pakai


def test_kode_akun_unik_dan_semua_kategori_pengeluaran_terpetakan() -> None:
    kode = [a.kode for a in AKUN_STANDAR]
    assert len(kode) == len(set(kode))
    assert set(AKUN_KATEGORI_PENGELUARAN) == set(KATEGORI_PENGELUARAN), "setiap kategori pengeluaran punya akun"
    for k in AKUN_KATEGORI_PENGELUARAN.values():
        assert AKUN_PER_KODE[k].kelompok in {"hpp", "beban"}
    assert AKUN_PER_KODE[AKUN_KATEGORI_PENGELUARAN["sewa"]].nama == "Beban sewa"
    assert AKUN_PER_KODE[AKUN_KATEGORI_PENGELUARAN["listrik_air"]].nama == "Beban listrik & air"


def test_akun_usulan_untuk_baris_ekspor() -> None:
    assert akun_untuk_baris_ekspor("penjualan_bersih", "").kode == "4-1000"
    assert akun_untuk_baris_ekspor("pajak_dipungut", "").kode == "2-1200"
    assert akun_untuk_baris_ekspor("hpp", "").kode == "5-1000"
    assert akun_untuk_baris_ekspor("penerimaan", "Tunai").kode == "1-1100"
    assert akun_untuk_baris_ekspor("penerimaan", "Qris").kode == "1-1200"
    assert akun_untuk_baris_ekspor("biaya", "sewa").kode == "6-1100"
    assert akun_untuk_baris_ekspor("biaya", "tidak_dikenal") is None
    baris = list(csv.reader(io.StringIO(ke_csv([("2026-11-02", "biaya", "listrik_air", 5)]))))
    assert baris[1][4:] == ["6-1200", "Beban listrik & air"]


async def test_endpoint_coa_dan_gerbang_paket(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    r = await client.get("/akuntansi/coa", headers=toko.headers)
    assert r.status_code == 200, r.text
    data = r.json()
    assert len(data["akun"]) == len(AKUN_STANDAR)
    assert {"kategori": "sewa", "kode_akun": "6-1100"} in data["pemetaan_pengeluaran"]

    gratis = await buat_toko_siap_pakai(db_session, nama_paket="Gratis")
    assert (await client.get("/akuntansi/coa", headers=gratis.headers)).status_code == 403

    kasir = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis", nama_role="Kasir")
    assert (await client.get("/akuntansi/coa", headers=kasir.headers)).status_code == 403
