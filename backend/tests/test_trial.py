"""Masa trial berdasarkan usia akun (arahan lead 2026-11-08): semua fitur
paket tertinggi terbuka selama usia akun toko belum mencapai batas
(`pengaturan_platform.usia_akun_bulan`), setelah itu paket langganan
berlaku normal."""

from datetime import UTC, datetime, timedelta

from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.models.audit import Notifikasi
from app.models.outlet import Langganan, Paket, Toko
from app.services.fitur_service import (
    has_fitur,
    paket_efektif,
    tambah_bulan,
    trial_toko,
)
from app.services.jobs_service import cek_trial_hampir_berakhir_dan_notifikasi
from app.services.platform_service import KUNCI_USIA_AKUN_BULAN, simpan_int


async def _umur_toko(db: AsyncSession, toko: Toko, *, hari: int) -> None:
    toko.created_at = datetime.now(UTC) - timedelta(days=hari)
    await db.commit()


async def test_tanpa_pengaturan_trial_mati_dan_paket_berlaku_sejak_hari_pertama(
    db_session: AsyncSession, toko_a
) -> None:
    assert await trial_toko(db_session, toko_a.toko.id) is None
    assert (await paket_efektif(db_session, toko_a.toko.id)).nama == "Gratis"
    assert not await has_fitur(db_session, toko_a.toko.id, "kasbon")


async def test_trial_aktif_membuka_semua_fitur_paket_tertinggi(db_session: AsyncSession, toko_a) -> None:
    await simpan_int(db_session, KUNCI_USIA_AKUN_BULAN, 4)

    trial = await trial_toko(db_session, toko_a.toko.id)
    assert trial is not None and trial.aktif
    assert 119 <= trial.hari_tersisa <= 123  # sekitar 4 bulan dari sekarang

    efektif = await paket_efektif(db_session, toko_a.toko.id)
    assert efektif.nama == "Bisnis"
    assert efektif.maks_produk is None and efektif.maks_pengguna is None
    for kode in ("kasbon", "tiket_dapur", "harga_grosir", "bundling"):
        assert await has_fitur(db_session, toko_a.toko.id, kode), kode


async def test_trial_berakhir_setelah_batas_usia_akun(db_session: AsyncSession, toko_a) -> None:
    await simpan_int(db_session, KUNCI_USIA_AKUN_BULAN, 4)
    await _umur_toko(db_session, toko_a.toko, hari=130)

    trial = await trial_toko(db_session, toko_a.toko.id)
    assert trial is not None and not trial.aktif and trial.hari_tersisa == 0
    assert (await paket_efektif(db_session, toko_a.toko.id)).nama == "Gratis"
    assert not await has_fitur(db_session, toko_a.toko.id, "kasbon")


async def test_durasi_trial_dapat_diubah_dan_langsung_berlaku(db_session: AsyncSession, toko_a) -> None:
    await _umur_toko(db_session, toko_a.toko, hari=100)
    await simpan_int(db_session, KUNCI_USIA_AKUN_BULAN, 3)
    assert (await paket_efektif(db_session, toko_a.toko.id)).nama == "Gratis"  # 100 hari > 3 bulan

    await simpan_int(db_session, KUNCI_USIA_AKUN_BULAN, 6)
    assert (await paket_efektif(db_session, toko_a.toko.id)).nama == "Bisnis"  # masih dalam 6 bulan

    await simpan_int(db_session, KUNCI_USIA_AKUN_BULAN, 0)  # 0 = dimatikan
    assert (await paket_efektif(db_session, toko_a.toko.id)).nama == "Gratis"


async def test_toko_yang_sudah_berlangganan_lebih_tinggi_tidak_diturunkan(db_session: AsyncSession, toko_a) -> None:
    await simpan_int(db_session, KUNCI_USIA_AKUN_BULAN, 4)
    bisnis = (await db_session.execute(select(Paket).where(Paket.nama == "Bisnis"))).scalar_one()
    await db_session.execute(
        Langganan.__table__.update().where(Langganan.toko_id == toko_a.toko.id).values(paket_id=bisnis.id)
    )
    await db_session.commit()
    assert (await paket_efektif(db_session, toko_a.toko.id)).nama == "Bisnis"


async def test_langganan_saya_menampilkan_status_trial(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    await simpan_int(db_session, KUNCI_USIA_AKUN_BULAN, 4)

    body = (await client.get("/langganan/saya", headers=toko_a.headers)).json()
    assert body["paket_nama"] == "Gratis"  # paket langganan tercatat tidak berubah
    assert body["paket_efektif_nama"] == "Bisnis"
    assert body["trial_aktif"] is True
    assert body["trial_durasi_bulan"] == 4
    assert body["trial_berakhir"] is not None
    assert 119 <= body["trial_hari_tersisa"] <= 123


async def test_langganan_saya_tanpa_trial_tetap_kompatibel(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    body = (await client.get("/langganan/saya", headers=toko_a.headers)).json()
    assert body["trial_aktif"] is False
    assert body["trial_berakhir"] is None
    assert body["paket_efektif_nama"] == "Gratis"


async def test_fitur_terkunci_di_server_terbuka_saat_trial(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    antes = await client.post("/promo", headers=toko_a.headers, json={"nama": "Hemat", "tipe": "persen", "nilai": "10"})
    assert antes.status_code == 403  # paket Gratis tanpa trial

    await simpan_int(db_session, KUNCI_USIA_AKUN_BULAN, 4)
    sesudah = await client.post(
        "/promo", headers=toko_a.headers, json={"nama": "Hemat", "tipe": "persen", "nilai": "10"}
    )
    assert sesudah.status_code != 403


async def test_notifikasi_trial_dibuat_sekali_saat_sisa_7_hari_atau_kurang(
    db_session: AsyncSession, toko_a
) -> None:
    await simpan_int(db_session, KUNCI_USIA_AKUN_BULAN, 4)

    # Baru mendaftar: sisa ~120 hari -> belum ada notifikasi.
    assert await cek_trial_hampir_berakhir_dan_notifikasi(db_session) == 0

    # Usia ~ 4 bulan dikurangi 5 hari -> sisa ~5 hari -> dibuat satu kali.
    toko_a.toko.created_at = tambah_bulan(datetime.now(UTC), -4) + timedelta(days=5)
    await db_session.commit()

    assert await cek_trial_hampir_berakhir_dan_notifikasi(db_session) == 1
    assert await cek_trial_hampir_berakhir_dan_notifikasi(db_session) == 0  # tidak duplikat

    notif = (
        await db_session.execute(select(Notifikasi).where(Notifikasi.toko_id == toko_a.toko.id))
    ).scalars().all()
    assert len(notif) == 1
    assert "berakhir dalam" in notif[0].judul and "Bisnis" in notif[0].judul


async def test_tidak_ada_notifikasi_bila_trial_sudah_berakhir(db_session: AsyncSession, toko_a) -> None:
    await simpan_int(db_session, KUNCI_USIA_AKUN_BULAN, 4)
    await _umur_toko(db_session, toko_a.toko, hari=200)
    assert await cek_trial_hampir_berakhir_dan_notifikasi(db_session) == 0


def test_tambah_bulan_kalender_menangani_akhir_bulan() -> None:
    assert tambah_bulan(datetime(2026, 10, 31, tzinfo=UTC), 4) == datetime(2027, 2, 28, tzinfo=UTC)
    assert tambah_bulan(datetime(2027, 11, 8, tzinfo=UTC), 4) == datetime(2028, 3, 8, tzinfo=UTC)
    assert tambah_bulan(datetime(2026, 11, 8, tzinfo=UTC), -4) == datetime(2026, 7, 8, tzinfo=UTC)


async def test_endpoint_admin_pengaturan_platform(
    client: AsyncClient, db_session: AsyncSession, monkeypatch
) -> None:
    assert (await client.get("/admin/pengaturan-platform")).status_code == 401

    monkeypatch.setenv("ADMIN_API_KEY", "kunci-rahasia-tes")
    get_settings.cache_clear()
    try:
        kunci = {"X-Admin-Api-Key": "kunci-rahasia-tes"}
        awal = (await client.get("/admin/pengaturan-platform", headers=kunci)).json()
        assert awal["usia_akun_bulan"] == 0 and awal["trial_notifikasi_hari"] == 7

        resp = await client.put("/admin/pengaturan-platform", headers=kunci, json={"usia_akun_bulan": 4})
        assert resp.status_code == 200 and resp.json()["usia_akun_bulan"] == 4

        kosong = await client.put("/admin/pengaturan-platform", headers=kunci, json={})
        assert kosong.status_code == 422
        salah = await client.put("/admin/pengaturan-platform", headers=kunci, json={"usia_akun_bulan": -1})
        assert salah.status_code == 422
    finally:
        get_settings.cache_clear()
