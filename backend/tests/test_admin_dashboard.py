"""Dashboard Administrator: status fitur (berkas -> database), ringkasan usaha,
daftar usaha, dan filter jenis usaha F&B."""

import json
from collections import Counter

import pytest
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.models.fitur import Fitur, FiturKebutuhan
from app.services.platform_service import KUNCI_USIA_AKUN_BULAN, simpan_int
from app.services.status_fitur_service import baca_berkas_status, sinkron_status_fitur
from tests.conftest import buat_toko_siap_pakai

KUNCI = {"X-Admin-Api-Key": "kunci-rahasia-tes"}


@pytest.fixture
def admin_aktif(monkeypatch):
    monkeypatch.setenv("ADMIN_API_KEY", "kunci-rahasia-tes")
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


async def _beri_nomor(db: AsyncSession) -> list[Fitur]:
    """Fitur seed uji belum bernomor IMOGI - beri nomor 1..3 supaya dashboard melihatnya."""
    rows = (await db.execute(select(Fitur).order_by(Fitur.kode).limit(3))).scalars().all()
    for i, f in enumerate(rows, start=1):
        f.nomor_imogi = i
        f.status_dev = "belum"
    await db.commit()
    return list(rows)


def test_berkas_status_nyata_valid_dan_cocok_dengan_gap_imogi() -> None:
    data = baca_berkas_status()
    assert sorted(data) == list(range(1, 88))
    hitung = Counter(v["status"] for v in data.values())
    # Angka ini harus sama dengan docs/gap_imogi.md; ubah KEDUANYA bersamaan.
    assert hitung == {"sudah": 15, "sedang": 39, "belum": 10, "tidak_relevan": 23}
    # Tes otomatis bukan bukti uji HP: tidak ada fitur yang boleh bertanda lulus uji HP tanpa bukti.
    assert not any(v.get("uji_hp") for v in data.values())


async def test_sinkron_status_fitur_memperbarui_dan_menolak_status_aneh(db_session: AsyncSession, tmp_path) -> None:
    fitur = await _beri_nomor(db_session)
    berkas = tmp_path / "status.json"
    berkas.write_text(json.dumps({"1": {"status": "sudah", "catatan": "selesai"}, "2": {"status": "sedang"}}))

    jumlah = await sinkron_status_fitur(db_session, berkas)
    assert jumlah == 2
    await db_session.refresh(fitur[0])
    assert fitur[0].status_dev == "sudah" and fitur[0].catatan_dev == "selesai" and fitur[0].uji_hp is False

    # Idempoten: tidak ada perubahan pada jalan kedua.
    assert await sinkron_status_fitur(db_session, berkas) == 0

    rusak = tmp_path / "rusak.json"
    rusak.write_text(json.dumps({"1": {"status": "selesai-banget"}}))
    with pytest.raises(ValueError):
        await sinkron_status_fitur(db_session, rusak)


async def test_dashboard_butuh_admin(client: AsyncClient, toko_a, admin_aktif) -> None:
    for jalur in ("/admin/dashboard/ringkasan", "/admin/dashboard/usaha", "/admin/dashboard/fitur"):
        assert (await client.get(jalur)).status_code == 401
        assert (await client.get(jalur, headers=toko_a.headers)).status_code == 401
        assert (await client.get(jalur, headers=KUNCI)).status_code == 200


async def test_jenis_usaha_tidak_dikenal_ditolak(client: AsyncClient, admin_aktif) -> None:
    resp = await client.get("/admin/dashboard/ringkasan", headers=KUNCI, params={"jenis_usaha": "XYZ"})
    assert resp.status_code == 422
    pilihan = await client.get("/admin/dashboard/jenis-usaha", headers=KUNCI)
    assert [p["kode"] for p in pilihan.json()] == ["CAF", "RES", "CAT", "BRD", "FRZ", "BEV", "STL"]


async def test_ringkasan_dan_daftar_usaha_dengan_filter(
    client: AsyncClient, db_session: AsyncSession, admin_aktif
) -> None:
    kafe = await buat_toko_siap_pakai(db_session, nama_paket="Gratis")
    kafe.toko.jenis_usaha = "CAF"
    kafe.toko.nama = "Kopi Senja"
    resto = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    resto.toko.jenis_usaha = "RES"
    resto.toko.nama = "Warung Makan Sedap"
    await db_session.commit()

    semua = (await client.get("/admin/dashboard/ringkasan", headers=KUNCI)).json()
    assert semua["total_usaha"] == 2
    assert semua["total_pengguna"] == 2
    assert {j["kode"]: j["jumlah"] for j in semua["per_jenis_usaha"]} == {"CAF": 1, "RES": 1}
    assert semua["trial"]["aktif_diatur"] is False  # pengaturan trial belum diisi

    cuma_kafe = (await client.get("/admin/dashboard/ringkasan", headers=KUNCI, params={"jenis_usaha": "caf"})).json()
    assert cuma_kafe["total_usaha"] == 1 and cuma_kafe["jenis_usaha"] == "CAF"

    daftar = (await client.get("/admin/dashboard/usaha", headers=KUNCI, params={"jenis_usaha": "RES"})).json()
    assert [u["nama"] for u in daftar] == ["Warung Makan Sedap"]
    assert daftar[0]["jenis_usaha_nama"] == "Restoran"
    assert daftar[0]["jumlah_pengguna"] == 1 and daftar[0]["jumlah_outlet"] == 1
    assert daftar[0]["paket_langganan"] == "Bisnis" and daftar[0]["status_langganan"] == "aktif"

    cari = (await client.get("/admin/dashboard/usaha", headers=KUNCI, params={"q": "senja"})).json()
    assert [u["nama"] for u in cari] == ["Kopi Senja"]
    assert cari[0]["paket_langganan"] == "Gratis"


async def test_trial_dihitung_di_ringkasan_dan_daftar(
    client: AsyncClient, db_session: AsyncSession, admin_aktif
) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Gratis")
    toko.toko.jenis_usaha = "BEV"
    await db_session.commit()
    await simpan_int(db_session, KUNCI_USIA_AKUN_BULAN, 4)

    ringkas = (await client.get("/admin/dashboard/ringkasan", headers=KUNCI)).json()
    assert ringkas["trial"]["aktif_diatur"] is True
    assert ringkas["trial"]["durasi_bulan"] == 4
    assert ringkas["trial"]["usaha_dalam_trial"] == 1
    assert ringkas["trial"]["usaha_trial_berakhir"] == 0
    # Selama trial, paket efektif = paket tertinggi.
    assert ringkas["per_paket"] == [{"kode": "Bisnis", "nama": "Bisnis", "jumlah": 1}]

    usaha = (await client.get("/admin/dashboard/usaha", headers=KUNCI)).json()[0]
    assert usaha["trial_aktif"] is True and usaha["trial_hari_tersisa"] > 100
    assert usaha["paket"] == "Bisnis" and usaha["paket_langganan"] == "Gratis"


async def test_fitur_disaring_menurut_jenis_usaha(
    client: AsyncClient, db_session: AsyncSession, admin_aktif
) -> None:
    fitur = await _beri_nomor(db_session)
    fitur[0].status_dev = "sudah"
    fitur[1].status_dev = "sedang"
    db_session.add(FiturKebutuhan(fitur_id=fitur[0].id, jenis_usaha="CAF", kebutuhan="inti"))
    db_session.add(FiturKebutuhan(fitur_id=fitur[1].id, jenis_usaha="CAF", kebutuhan="opsional"))
    db_session.add(FiturKebutuhan(fitur_id=fitur[2].id, jenis_usaha="CAF", kebutuhan="na"))
    db_session.add(FiturKebutuhan(fitur_id=fitur[0].id, jenis_usaha="CAT", kebutuhan="na"))
    await db_session.commit()

    tanpa_filter = (await client.get("/admin/dashboard/fitur", headers=KUNCI)).json()
    assert [f["nomor"] for f in tanpa_filter] == [1, 2, 3]
    assert [f["status"] for f in tanpa_filter] == ["sudah", "sedang", "belum"]
    assert all(f["kebutuhan"] is None for f in tanpa_filter)

    kafe = {f["nomor"]: f for f in (await client.get("/admin/dashboard/fitur", headers=KUNCI, params={"jenis_usaha": "CAF"})).json()}
    assert kafe[1]["kebutuhan"] == "inti" and kafe[1]["status"] == "sudah"
    assert kafe[2]["kebutuhan"] == "opsional"
    assert kafe[3]["status"] == "tidak_relevan"  # 'na' untuk kafe

    katering = {f["nomor"]: f for f in (await client.get("/admin/dashboard/fitur", headers=KUNCI, params={"jenis_usaha": "CAT"})).json()}
    assert katering[1]["status"] == "tidak_relevan"  # fitur 1 'na' untuk katering walau 'sudah' secara kode
    assert katering[1]["status_dev"] == "sudah"

    ringkas = (await client.get("/admin/dashboard/ringkasan", headers=KUNCI, params={"jenis_usaha": "CAF"})).json()
    assert ringkas["fitur"] == {"sudah": 1, "sedang": 1, "belum": 0, "tidak_relevan": 1, "uji_hp": 0, "total": 3}
