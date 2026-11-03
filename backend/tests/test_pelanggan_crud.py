"""Tahap 5 B.1/B.7 - PATCH/DELETE pelanggan, level_member CRUD (gate
diskon_member), aturan_poin CRUD (gate poin_loyalitas), riwayat_poin."""

import uuid
from decimal import Decimal

from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import create_access_token
from app.models.akun import Pengguna, Role
from app.models.audit import AuditLog
from app.models.pelanggan import Pelanggan, RiwayatPoin
from tests.conftest import buat_toko_siap_pakai


async def test_ubah_pelanggan_termasuk_batas_kasbon_tercatat_audit(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    pelanggan = Pelanggan(toko_id=toko_a.toko.id, nama="Budi")
    db_session.add(pelanggan)
    await db_session.commit()

    resp = await client.patch(
        f"/pelanggan/{pelanggan.id}", headers=toko_a.headers,
        json={"nama": "Budi Santoso", "batas_kasbon": "500000"},
    )
    assert resp.status_code == 200
    assert resp.json()["nama"] == "Budi Santoso"
    assert Decimal(resp.json()["batas_kasbon"]) == Decimal("500000")

    audit = (await db_session.execute(select(AuditLog).where(AuditLog.aksi == "ubah_pelanggan"))).scalar_one()
    assert audit.data_baru["nama"] == "Budi Santoso"


async def test_hapus_pelanggan_soft_delete(client: AsyncClient, db_session: AsyncSession, toko_a) -> None:
    pelanggan = Pelanggan(toko_id=toko_a.toko.id, nama="Budi")
    db_session.add(pelanggan)
    await db_session.commit()

    resp = await client.delete(f"/pelanggan/{pelanggan.id}", headers=toko_a.headers)
    assert resp.status_code == 204
    await db_session.refresh(pelanggan)
    assert pelanggan.deleted_at is not None

    resp2 = await client.get(f"/pelanggan/{pelanggan.id}", headers=toko_a.headers)
    assert resp2.status_code == 404


async def test_level_member_digate_fitur_diskon_member(client: AsyncClient, db_session: AsyncSession) -> None:
    toko_gratis = await buat_toko_siap_pakai(db_session, nama_paket="Gratis")
    resp = await client.post("/level-member", headers=toko_gratis.headers, json={"nama": "Gold"})
    assert resp.status_code == 403
    assert resp.json()["detail"]["kode"] == "fitur_terkunci"


async def test_level_member_crud_dgn_fitur_terbuka(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    resp = await client.post(
        "/level-member", headers=toko.headers,
        json={"nama": "Gold", "diskon_persen": "5", "pengali_poin": "2"},
    )
    assert resp.status_code == 201
    level_id = resp.json()["id"]

    resp2 = await client.patch(f"/level-member/{level_id}", headers=toko.headers, json={"nama": "Gold Plus"})
    assert resp2.status_code == 200
    assert resp2.json()["nama"] == "Gold Plus"

    # Pelanggan yang menautkan level ini harus dilepas (NULL) saat dihapus.
    pelanggan = Pelanggan(toko_id=toko.toko.id, nama="Budi", level_member_id=uuid.UUID(level_id))
    db_session.add(pelanggan)
    await db_session.commit()

    resp3 = await client.delete(f"/level-member/{level_id}", headers=toko.headers)
    assert resp3.status_code == 204
    await db_session.refresh(pelanggan)
    assert pelanggan.level_member_id is None


async def test_role_tanpa_izin_pelanggan_kelola_tambah_level_member_ditolak(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    """Ketiga role bawaan (Owner/Manajer/Kasir) semua PUNYA izin
    pelanggan.kelola (lihat seed.py) - jadi rejection cuma bisa dibuktikan
    lewat role custom tanpa izin apa pun sama sekali."""
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    role_kosong = Role(toko_id=toko.toko.id, nama="Role Tanpa Izin", is_system=False)
    db_session.add(role_kosong)
    await db_session.flush()
    staf = Pengguna(toko_id=toko.toko.id, role_id=role_kosong.id, nama="Staf Baru")
    db_session.add(staf)
    await db_session.commit()
    token_staf = create_access_token(pengguna_id=staf.id, toko_id=toko.toko.id, role_id=role_kosong.id)

    resp = await client.post(
        "/level-member", headers={"Authorization": f"Bearer {token_staf}"}, json={"nama": "Gold"}
    )
    assert resp.status_code == 403


async def test_aturan_poin_digate_fitur_poin_loyalitas(client: AsyncClient, db_session: AsyncSession) -> None:
    toko_gratis = await buat_toko_siap_pakai(db_session, nama_paket="Gratis")
    resp = await client.put("/aturan-poin", headers=toko_gratis.headers, json={})
    assert resp.status_code == 403
    assert resp.json()["detail"]["kode"] == "fitur_terkunci"


async def test_aturan_poin_upsert_dan_patch(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")

    resp_kosong = await client.get("/aturan-poin", headers=toko.headers)
    assert resp_kosong.status_code == 200
    assert resp_kosong.json() is None

    resp = await client.put(
        "/aturan-poin", headers=toko.headers,
        json={"nominal_per_poin": "5000", "nilai_tukar_poin": "50"},
    )
    assert resp.status_code == 200
    assert Decimal(resp.json()["nominal_per_poin"]) == Decimal("5000")

    resp2 = await client.patch("/aturan-poin", headers=toko.headers, json={"aktif": False})
    assert resp2.status_code == 200
    assert resp2.json()["aktif"] is False
    assert Decimal(resp2.json()["nominal_per_poin"]) == Decimal("5000")

    audit_rows = (
        await db_session.execute(select(AuditLog).where(AuditLog.aksi.in_(["atur_aturan_poin", "ubah_aturan_poin"])))
    ).scalars().all()
    assert len(audit_rows) == 2


async def test_riwayat_poin_pelanggan(client: AsyncClient, db_session: AsyncSession, toko_a) -> None:
    pelanggan = Pelanggan(toko_id=toko_a.toko.id, nama="Budi")
    db_session.add(pelanggan)
    await db_session.flush()
    db_session.add(RiwayatPoin(pelanggan_id=pelanggan.id, poin=10, keterangan="Dari transaksi"))
    db_session.add(RiwayatPoin(pelanggan_id=pelanggan.id, poin=-5, keterangan="Tukar poin"))
    await db_session.commit()

    resp = await client.get(f"/pelanggan/{pelanggan.id}/riwayat-poin", headers=toko_a.headers)
    assert resp.status_code == 200
    assert len(resp.json()) == 2
