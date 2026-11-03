"""Temuan#2 (rapikan F3.E) - jejak pembatalan pesanan tersimpan: alasan
wajib, audit_log (siapa/kapan/isi pesanan/total/alasan), approval PIN
owner/manajer utk Kasir di atas batas_approval_batal_pesanan (default
Rp0), online langsung DAN offline lewat /sync/push."""

import uuid
from datetime import UTC, datetime
from decimal import Decimal

from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import create_access_token
from app.models.akun import Pengguna, Role
from app.models.audit import AuditLog
from app.models.transaksi import Transaksi
from tests.conftest import buat_perangkat, buat_produk


async def _buat_kasir(db: AsyncSession, toko_id) -> tuple[Pengguna, str]:
    role = (await db.execute(select(Role).where(Role.nama == "Kasir", Role.is_system.is_(True)))).scalar_one()
    kasir = Pengguna(toko_id=toko_id, role_id=role.id, nama="Kasir Biasa")
    db.add(kasir)
    await db.commit()
    await db.refresh(kasir)
    token = create_access_token(pengguna_id=kasir.id, toko_id=toko_id, role_id=role.id)
    return kasir, token


async def _buat_draft(client: AsyncClient, toko, produk, *, harga_satuan: str = "15000", qty: str = "2") -> str:
    pesanan_id = str(uuid.uuid4())
    resp = await client.post(
        "/transaksi/pesanan-tersimpan",
        headers=toko.headers,
        json={
            "id": pesanan_id,
            "outlet_id": str(toko.outlet.id),
            "nomor_struk": f"DRAFT-{pesanan_id[:8]}",
            "tanggal": datetime.now(UTC).isoformat(),
            "items": [
                {"produk_id": str(produk.id), "nama_produk": produk.nama, "qty": qty, "harga_satuan": harga_satuan}
            ],
        },
    )
    assert resp.status_code == 201
    return pesanan_id


async def test_owner_batalkan_sendiri_tanpa_approval(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id)
    pesanan_id = await _buat_draft(client, toko_a, produk)

    resp = await client.post(
        f"/transaksi/pesanan-tersimpan/{pesanan_id}/batalkan",
        headers=toko_a.headers,
        json={"alasan": "Pelanggan berubah pikiran"},
    )
    assert resp.status_code == 204, resp.text
    assert await db_session.get(Transaksi, uuid.UUID(pesanan_id)) is None

    audit = (
        await db_session.execute(
            select(AuditLog).where(
                AuditLog.aksi == "batalkan_pesanan_tersimpan", AuditLog.record_id == uuid.UUID(pesanan_id)
            )
        )
    ).scalar_one()
    assert audit.pengguna_id == toko_a.pengguna.id
    assert audit.data_baru["alasan"] == "Pelanggan berubah pikiran"
    assert audit.data_baru["disetujui_oleh"] is None
    assert audit.data_lama["isi_pesanan"][0]["nama_produk"] == produk.nama
    assert Decimal(audit.data_lama["total"]) == Decimal("30000.00")


async def test_kasir_batalkan_tanpa_approval_ditolak(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id)
    pesanan_id = await _buat_draft(client, toko_a, produk)
    _, token_kasir = await _buat_kasir(db_session, toko_a.toko.id)

    resp = await client.post(
        f"/transaksi/pesanan-tersimpan/{pesanan_id}/batalkan",
        headers={"Authorization": f"Bearer {token_kasir}"},
        json={"alasan": "Coba batal"},
    )
    assert resp.status_code == 403
    assert resp.json()["detail"]["kode"] == "batal_pesanan_butuh_approval"
    assert await db_session.get(Transaksi, uuid.UUID(pesanan_id)) is not None


async def test_kasir_batalkan_approval_tidak_sah_ditolak(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id)
    pesanan_id = await _buat_draft(client, toko_a, produk)
    kasir_1, token_kasir_1 = await _buat_kasir(db_session, toko_a.toko.id)
    kasir_2, _ = await _buat_kasir(db_session, toko_a.toko.id)

    resp = await client.post(
        f"/transaksi/pesanan-tersimpan/{pesanan_id}/batalkan",
        headers={"Authorization": f"Bearer {token_kasir_1}"},
        json={"alasan": "Coba batal", "disetujui_oleh": str(kasir_2.id)},
    )
    assert resp.status_code == 403
    assert resp.json()["detail"]["kode"] == "batal_pesanan_approval_tidak_sah"


async def test_kasir_batalkan_dgn_approval_owner_sah_diterima(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id)
    pesanan_id = await _buat_draft(client, toko_a, produk)
    kasir, token_kasir = await _buat_kasir(db_session, toko_a.toko.id)

    resp = await client.post(
        f"/transaksi/pesanan-tersimpan/{pesanan_id}/batalkan",
        headers={"Authorization": f"Bearer {token_kasir}"},
        json={"alasan": "Disetujui owner", "disetujui_oleh": str(toko_a.pengguna.id)},
    )
    assert resp.status_code == 204, resp.text

    audit = (
        await db_session.execute(
            select(AuditLog).where(
                AuditLog.aksi == "batalkan_pesanan_tersimpan", AuditLog.record_id == uuid.UUID(pesanan_id)
            )
        )
    ).scalar_one()
    assert audit.pengguna_id == kasir.id
    assert audit.data_baru["disetujui_oleh"] == str(toko_a.pengguna.id)


async def test_kasir_batalkan_pesanan_total_nol_tanpa_approval(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    """Default batas_approval_batal_pesanan = Rp0 - pesanan dgn total PAS
    0 (harga_satuan 0) jadi tidak di atas batas, jadi TIDAK butuh approval
    sama sekali walau yang membatalkan Kasir."""
    produk = await buat_produk(db_session, toko_a.toko.id)
    pesanan_id = await _buat_draft(client, toko_a, produk, harga_satuan="0")
    _, token_kasir = await _buat_kasir(db_session, toko_a.toko.id)

    resp = await client.post(
        f"/transaksi/pesanan-tersimpan/{pesanan_id}/batalkan",
        headers={"Authorization": f"Bearer {token_kasir}"},
        json={"alasan": "Pesanan gratis dibatalkan"},
    )
    assert resp.status_code == 204, resp.text


async def test_batalkan_tanpa_alasan_ditolak(client: AsyncClient, db_session: AsyncSession, toko_a) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id)
    pesanan_id = await _buat_draft(client, toko_a, produk)

    resp = await client.post(
        f"/transaksi/pesanan-tersimpan/{pesanan_id}/batalkan",
        headers=toko_a.headers,
        json={"alasan": "   "},
    )
    assert resp.status_code == 400
    assert await db_session.get(Transaksi, uuid.UUID(pesanan_id)) is not None


async def test_batalkan_pesanan_sudah_hilang_idempotent(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    resp = await client.post(
        f"/transaksi/pesanan-tersimpan/{uuid.uuid4()}/batalkan",
        headers=toko_a.headers,
        json={"alasan": "sudah tidak ada"},
    )
    assert resp.status_code == 204


async def test_batalkan_pesanan_via_sync_push_offline(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id)
    pesanan_id = await _buat_draft(client, toko_a, produk)
    kasir, token_kasir = await _buat_kasir(db_session, toko_a.toko.id)
    perangkat = await buat_perangkat(db_session, toko_a.toko.id, toko_a.outlet.id)

    resp = await client.post(
        "/sync/push",
        headers={"Authorization": f"Bearer {token_kasir}"},
        json={
            "perangkat_id": str(perangkat.id),
            "pesanan_batal": [
                {"id": pesanan_id, "alasan": "Dibatalkan offline", "disetujui_oleh": str(toko_a.pengguna.id)}
            ],
        },
    )
    assert resp.status_code == 200, resp.text
    assert resp.json()["pesanan_batal"] == [{"id": pesanan_id, "status": "diterima", "pesan": None}]
    assert await db_session.get(Transaksi, uuid.UUID(pesanan_id)) is None

    audit = (
        await db_session.execute(
            select(AuditLog).where(
                AuditLog.aksi == "batalkan_pesanan_tersimpan", AuditLog.record_id == uuid.UUID(pesanan_id)
            )
        )
    ).scalar_one()
    assert audit.pengguna_id == kasir.id
    assert audit.data_baru["alasan"] == "Dibatalkan offline"


async def test_batalkan_pesanan_via_sync_push_tanpa_approval_ditolak(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id)
    pesanan_id = await _buat_draft(client, toko_a, produk)
    _, token_kasir = await _buat_kasir(db_session, toko_a.toko.id)
    perangkat = await buat_perangkat(db_session, toko_a.toko.id, toko_a.outlet.id)

    resp = await client.post(
        "/sync/push",
        headers={"Authorization": f"Bearer {token_kasir}"},
        json={
            "perangkat_id": str(perangkat.id),
            "pesanan_batal": [{"id": pesanan_id, "alasan": "Coba offline"}],
        },
    )
    assert resp.status_code == 200
    hasil = resp.json()["pesanan_batal"][0]
    assert hasil["status"] == "ditolak"
    assert await db_session.get(Transaksi, uuid.UUID(pesanan_id)) is not None


async def test_laporan_owner_pesanan_dibatalkan_per_kasir(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    """Bukan endpoint baru - GET /audit-log?tabel=transaksi&aksi=... (filter
    `aksi` baru) sudah cukup utk "daftar pesanan dibatalkan per kasir":
    AuditLogOut.pengguna_id = siapa yg membatalkan, created_at = kapan."""
    produk = await buat_produk(db_session, toko_a.toko.id)
    pesanan_1 = await _buat_draft(client, toko_a, produk)
    pesanan_2 = await _buat_draft(client, toko_a, produk)
    kasir, token_kasir = await _buat_kasir(db_session, toko_a.toko.id)

    await client.post(
        f"/transaksi/pesanan-tersimpan/{pesanan_1}/batalkan",
        headers={"Authorization": f"Bearer {token_kasir}"},
        json={"alasan": "batal 1", "disetujui_oleh": str(toko_a.pengguna.id)},
    )
    await client.post(
        f"/transaksi/pesanan-tersimpan/{pesanan_2}/batalkan",
        headers=toko_a.headers,
        json={"alasan": "batal 2 oleh owner"},
    )

    resp = await client.get(
        "/audit-log",
        headers=toko_a.headers,
        params={"tabel": "transaksi", "aksi": "batalkan_pesanan_tersimpan"},
    )
    assert resp.status_code == 200
    rows = resp.json()
    assert len(rows) == 2
    per_kasir = {r["pengguna_id"]: r for r in rows}
    assert str(kasir.id) in per_kasir
    assert str(toko_a.pengguna.id) in per_kasir
