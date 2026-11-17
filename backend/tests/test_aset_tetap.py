"""IMOGI no. 83: aset tetap & penyusutan garis lurus."""

import uuid
from datetime import date
from decimal import Decimal

from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.aset_tetap import AsetTetap
from app.routers.aset_tetap import hitung_penyusutan
from tests.conftest import buat_toko_siap_pakai


def _aset(harga: str, residu: str, umur: int, tgl: date) -> AsetTetap:
    return AsetTetap(
        id=uuid.uuid4(),
        nama="Mesin",
        tanggal_perolehan=tgl,
        harga_perolehan=Decimal(harga),
        nilai_residu=Decimal(residu),
        umur_bulan=umur,
    )


def test_penyusutan_garis_lurus_per_bulan() -> None:
    a = _aset("12000000", "0", 12, date(2026, 1, 15))
    jan = hitung_penyusutan(a, date(2026, 1, 31))
    assert jan.penyusutan_per_bulan == Decimal("1000000.00")
    assert jan.bulan_berjalan == 1 and jan.akumulasi_penyusutan == Decimal("1000000.00")
    assert jan.penyusutan_bulan_ini == Decimal("1000000.00")
    mar = hitung_penyusutan(a, date(2026, 3, 1))
    assert mar.akumulasi_penyusutan == Decimal("3000000.00") and mar.nilai_buku == Decimal("9000000.00")


def test_sebelum_perolehan_nol_dan_setelah_umur_berhenti_di_residu() -> None:
    a = _aset("10000000", "1000000", 9, date(2026, 6, 1))
    sebelum = hitung_penyusutan(a, date(2026, 5, 31))
    assert sebelum.bulan_berjalan == 0 and sebelum.nilai_buku == Decimal("10000000")
    selesai = hitung_penyusutan(a, date(2030, 1, 1))
    assert selesai.bulan_berjalan == 9
    assert selesai.nilai_buku == Decimal("1000000"), "berhenti di nilai residu"
    assert selesai.penyusutan_bulan_ini == Decimal("0")


def test_sisa_pembulatan_diserap_bulan_terakhir() -> None:
    a = _aset("1000", "0", 3, date(2026, 1, 1))  # 333,33 per bulan
    akhir = hitung_penyusutan(a, date(2026, 3, 31))
    assert akhir.akumulasi_penyusutan == Decimal("1000")
    assert akhir.penyusutan_bulan_ini == Decimal("1000") - Decimal("666.66")


async def test_crud_dan_ringkasan(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    body = {
        "nama": "Espresso machine",
        "tanggal_perolehan": "2026-01-10",
        "harga_perolehan": "24000000",
        "nilai_residu": "0",
        "umur_bulan": 24,
    }
    r = await client.post("/aset-tetap", headers=toko.headers, json=body)
    assert r.status_code == 201, r.text
    aset_id = r.json()["id"]
    await client.post("/aset-tetap", headers=toko.headers, json={**body, "nama": "Kulkas", "tanggal_perolehan": "2027-01-01"})

    ringkas = (await client.get("/aset-tetap", headers=toko.headers, params={"per": "2026-03-31"})).json()
    assert len(ringkas["aset"]) == 1, "aset yang belum diperoleh tidak ikut"
    assert Decimal(ringkas["total_akumulasi"]) == 3000000
    assert Decimal(ringkas["total_nilai_buku"]) == 21000000
    assert Decimal(ringkas["total_penyusutan_bulan_ini"]) == 1000000

    ubah = await client.patch(f"/aset-tetap/{aset_id}", headers=toko.headers, json={"nama": "Mesin kopi"})
    assert ubah.json()["nama"] == "Mesin kopi"
    assert (await client.delete(f"/aset-tetap/{aset_id}", headers=toko.headers)).status_code == 204
    sisa = (await client.get("/aset-tetap", headers=toko.headers, params={"per": "2028-01-01"})).json()
    assert [a["nama"] for a in sisa["aset"]] == ["Kulkas"]


async def test_validasi_isolasi_dan_paket(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    lain = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    body = {"nama": "A", "tanggal_perolehan": "2026-01-01", "harga_perolehan": "1000", "umur_bulan": 12}
    assert (await client.post("/aset-tetap", headers=toko.headers, json={**body, "nilai_residu": "1000"})).status_code == 422
    assert (await client.post("/aset-tetap", headers=toko.headers, json={**body, "umur_bulan": 0})).status_code == 422
    dibuat = (await client.post("/aset-tetap", headers=toko.headers, json=body)).json()
    assert (await client.delete(f"/aset-tetap/{dibuat['id']}", headers=lain.headers)).status_code == 404
    gratis = await buat_toko_siap_pakai(db_session, nama_paket="Gratis")
    assert (await client.get("/aset-tetap", headers=gratis.headers)).status_code == 403


async def test_ubah_angka_aset_menghitung_ulang_dan_menjaga_residu(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    body = {"nama": "Oven", "tanggal_perolehan": "2026-01-10", "harga_perolehan": "12000000", "umur_bulan": 12}
    aset_id = (await client.post("/aset-tetap", headers=toko.headers, json=body)).json()["id"]

    ok = await client.patch(
        f"/aset-tetap/{aset_id}", headers=toko.headers, json={"harga_perolehan": "24000000", "umur_bulan": 24}
    )
    assert ok.status_code == 200, ok.text
    assert Decimal(ok.json()["penyusutan_per_bulan"]) == 1000000
    salah = await client.patch(f"/aset-tetap/{aset_id}", headers=toko.headers, json={"nilai_residu": "24000000"})
    assert salah.status_code == 422
    ringkas = (await client.get("/aset-tetap", headers=toko.headers, params={"per": "2026-01-31"})).json()
    assert Decimal(ringkas["aset"][0]["harga_perolehan"]) == 24000000, "angka tidak berubah oleh patch yang ditolak"


async def test_aset_ikut_terkunci_tutup_buku(client: AsyncClient, db_session: AsyncSession) -> None:
    from datetime import UTC, datetime, timedelta

    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    lama = str((datetime.now(UTC) - timedelta(days=20)).date())
    baru = str((datetime.now(UTC) - timedelta(days=1)).date())
    body = {"nama": "Blender", "tanggal_perolehan": lama, "harga_perolehan": "1000", "umur_bulan": 12}
    aset_id = (await client.post("/aset-tetap", headers=toko.headers, json=body)).json()["id"]
    await client.post("/tutup-buku", headers=toko.headers, json={"sampai": str((datetime.now(UTC) - timedelta(days=5)).date())})

    assert (await client.post("/aset-tetap", headers=toko.headers, json=body)).status_code == 409
    assert (await client.patch(f"/aset-tetap/{aset_id}", headers=toko.headers, json={"nama": "X"})).status_code == 409
    assert (await client.delete(f"/aset-tetap/{aset_id}", headers=toko.headers)).status_code == 409
    assert (await client.post("/aset-tetap", headers=toko.headers, json={**body, "tanggal_perolehan": baru})).status_code == 201
