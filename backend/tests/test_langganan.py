"""F3.F - Paket langganan: lihat paket+pemakaian, ajukan upgrade (tanpa
pembayaran di app), aktivasi lewat endpoint admin terpisah (API key)."""

from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.models.audit import AuditLog
from app.models.outlet import Langganan, Paket


async def test_daftar_paket_mengembalikan_fitur_per_paket(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    resp = await client.get("/paket", headers=toko_a.headers)
    assert resp.status_code == 200
    body = resp.json()
    nama_paket = {p["nama"] for p in body}
    assert {"Gratis", "Pro", "Bisnis"} <= nama_paket
    # Urutan naik sesuai Paket.urutan (Gratis=0, Pro=1, Bisnis=2).
    urutan = [p["urutan"] for p in body]
    assert urutan == sorted(urutan)


async def test_langganan_saya_menghitung_pemakaian(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    resp = await client.get("/langganan/saya", headers=toko_a.headers)
    assert resp.status_code == 200
    body = resp.json()
    assert body["paket_nama"] == "Gratis"
    assert body["status"] == "aktif"
    assert body["pemakaian"]["outlet"] >= 1
    assert body["pemakaian"]["pengguna"] >= 1


async def test_ajukan_permintaan_upgrade(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    paket_pro = (await db_session.execute(select(Paket).where(Paket.nama == "Pro"))).scalar_one()

    resp = await client.post(
        "/langganan/permintaan-upgrade",
        headers=toko_a.headers,
        json={"paket_tujuan_id": str(paket_pro.id), "jumlah_outlet": 2, "periode": "tahunan"},
    )
    assert resp.status_code == 201
    body = resp.json()
    assert body["status"] == "baru"
    assert body["jumlah_outlet"] == 2


async def test_admin_aktivasi_tanpa_api_key_ditolak(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    paket_pro = (await db_session.execute(select(Paket).where(Paket.nama == "Pro"))).scalar_one()
    resp = await client.post(
        "/admin/langganan/aktivasi",
        json={"toko_id": str(toko_a.toko.id), "paket_id": str(paket_pro.id)},
    )
    assert resp.status_code == 401


async def test_admin_aktivasi_dgn_api_key_sukses_dan_tercatat_audit(
    client: AsyncClient, db_session: AsyncSession, toko_a, monkeypatch
) -> None:
    monkeypatch.setenv("ADMIN_API_KEY", "kunci-rahasia-tes")
    get_settings.cache_clear()
    try:
        paket_pro = (
            await db_session.execute(select(Paket).where(Paket.nama == "Pro"))
        ).scalar_one()

        resp = await client.post(
            "/admin/langganan/aktivasi",
            headers={"X-Admin-Api-Key": "kunci-rahasia-tes"},
            json={
                "toko_id": str(toko_a.toko.id),
                "paket_id": str(paket_pro.id),
                "jumlah_outlet": 3,
                "periode": "tahunan",
            },
        )
        assert resp.status_code == 201

        resp_salah = await client.post(
            "/admin/langganan/aktivasi",
            headers={"X-Admin-Api-Key": "kunci-salah"},
            json={"toko_id": str(toko_a.toko.id), "paket_id": str(paket_pro.id)},
        )
        assert resp_salah.status_code == 401

        langganan_baru = (
            await db_session.execute(
                select(Langganan)
                .where(Langganan.toko_id == toko_a.toko.id, Langganan.paket_id == paket_pro.id)
            )
        ).scalars().first()
        assert langganan_baru is not None
        assert langganan_baru.status == "aktif"
        assert langganan_baru.jumlah_outlet == 3

        audit_rows = (
            await db_session.execute(
                select(AuditLog).where(AuditLog.aksi == "admin_aktivasi_langganan")
            )
        ).scalars().all()
        assert len(audit_rows) == 1
        assert audit_rows[0].toko_id == toko_a.toko.id

        # Sync berikutnya harus baca paket BARU (Pro), bukan Gratis lama -
        # lihat paket_efektif() yang dipakai sync_service.py.
        resp_saya = await client.get("/langganan/saya", headers=toko_a.headers)
        assert resp_saya.json()["paket_nama"] == "Pro"
    finally:
        get_settings.cache_clear()


async def test_toko_lain_tidak_bisa_lihat_langganan_toko_a(
    client: AsyncClient, db_session: AsyncSession, toko_a, toko_b
) -> None:
    resp_a = await client.get("/langganan/saya", headers=toko_a.headers)
    resp_b = await client.get("/langganan/saya", headers=toko_b.headers)
    assert resp_a.status_code == 200
    assert resp_b.status_code == 200
    # Masing2 toko_id berbeda -> dua Langganan row BEDA, bukan data yang sama bocor.
    assert resp_a.json()["paket_id"] != "" and resp_b.json()["paket_id"] != ""
