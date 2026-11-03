"""Tahap 5b - satukan identitas karyawan antara HP dan server. Lihat
app/services/identitas_service.py (validasi+tandai push) dan
app/routers/auth.py::pin_login (token online atas nama karyawan)."""

import uuid
from datetime import UTC, datetime
from decimal import Decimal

from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import hash_password
from app.models.akun import AksesOutlet, Pengguna, Role
from app.models.audit import AuditLog, Notifikasi
from app.models.outlet import Paket
from app.models.transaksi import KasShift, Shift, Transaksi
from tests.conftest import buat_metode_bayar, buat_perangkat, buat_produk, buat_toko_siap_pakai


async def _buat_kasir(
    db: AsyncSession, toko_id, outlet_id=None, *, pin: str = "123456", aktif: bool = True, nama: str = "Kasir Budi"
) -> Pengguna:
    kasir_role = (await db.execute(select(Role).where(Role.nama == "Kasir", Role.is_system.is_(True)))).scalar_one()
    kasir = Pengguna(toko_id=toko_id, role_id=kasir_role.id, nama=nama, pin_hash=hash_password(pin), aktif=aktif)
    db.add(kasir)
    await db.flush()
    if outlet_id is not None:
        db.add(AksesOutlet(pengguna_id=kasir.id, outlet_id=outlet_id))
    await db.commit()
    await db.refresh(kasir)
    return kasir


async def test_push_transaksi_menyimpan_pengguna_id_kasir_yang_sebenarnya(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    """Token yang dipakai push tetap token Owner/device (sama spt
    temuan Langkah 0), tapi pengguna_id yang TERCATAT di server harus
    pengguna_id KASIR yang eksplisit dikirim di body - bukan Owner."""
    kasir = await _buat_kasir(db_session, toko_a.toko.id, toko_a.outlet.id)
    produk = await buat_produk(db_session, toko_a.toko.id)
    metode = await buat_metode_bayar(db_session, toko_a.toko.id)
    perangkat = await buat_perangkat(db_session, toko_a.toko.id, toko_a.outlet.id)

    transaksi_id = str(uuid.uuid4())
    resp = await client.post(
        "/sync/push",
        headers=toko_a.headers,
        json={
            "perangkat_id": str(perangkat.id),
            "transaksi": [
                {
                    "id": transaksi_id,
                    "outlet_id": str(toko_a.outlet.id),
                    "nomor_struk": "OUT1-ID-0001",
                    "tanggal": datetime.now(UTC).isoformat(),
                    "items": [
                        {"produk_id": str(produk.id), "nama_produk": produk.nama, "qty": "1", "harga_satuan": "15000"}
                    ],
                    "metode_bayar_id": str(metode.id),
                    "total_bayar": "15000",
                    "pengguna_id": str(kasir.id),
                }
            ],
        },
    )
    assert resp.status_code == 200
    assert resp.json()["transaksi"][0]["status"] == "diterima"

    row = (await db_session.execute(select(Transaksi).where(Transaksi.id == uuid.UUID(transaksi_id)))).scalar_one()
    assert row.pengguna_id == kasir.id
    assert row.pengguna_id != toko_a.pengguna.id


async def test_push_shift_menyimpan_pengguna_id_kasir_yang_sebenarnya(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    kasir = await _buat_kasir(db_session, toko_a.toko.id, toko_a.outlet.id)
    perangkat = await buat_perangkat(db_session, toko_a.toko.id, toko_a.outlet.id)
    shift_id = str(uuid.uuid4())

    resp = await client.post(
        "/sync/push",
        headers=toko_a.headers,
        json={
            "perangkat_id": str(perangkat.id),
            "shift": [
                {
                    "id": shift_id,
                    "outlet_id": str(toko_a.outlet.id),
                    "dibuka_pada": datetime.now(UTC).isoformat(),
                    "modal_awal": "50000",
                    "pengguna_id": str(kasir.id),
                }
            ],
        },
    )
    assert resp.status_code == 200
    assert resp.json()["shift"][0]["status"] == "diterima"

    row = (await db_session.execute(select(Shift).where(Shift.id == uuid.UUID(shift_id)))).scalar_one()
    assert row.pengguna_id == kasir.id


async def test_push_kas_shift_menyimpan_pengguna_id_kasir_yang_sebenarnya(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    kasir = await _buat_kasir(db_session, toko_a.toko.id, toko_a.outlet.id)
    perangkat = await buat_perangkat(db_session, toko_a.toko.id, toko_a.outlet.id)
    shift_id = str(uuid.uuid4())
    kas_id = str(uuid.uuid4())

    resp = await client.post(
        "/sync/push",
        headers=toko_a.headers,
        json={
            "perangkat_id": str(perangkat.id),
            "shift": [
                {
                    "id": shift_id, "outlet_id": str(toko_a.outlet.id),
                    "dibuka_pada": datetime.now(UTC).isoformat(), "modal_awal": "50000",
                    "pengguna_id": str(kasir.id),
                }
            ],
            "kas_shift": [
                {
                    "id": kas_id, "shift_id": shift_id, "jenis": "keluar", "jumlah": "10000",
                    "keterangan": "beli galon", "pengguna_id": str(kasir.id),
                }
            ],
        },
    )
    assert resp.status_code == 200

    row = (await db_session.execute(select(KasShift).where(KasShift.id == uuid.UUID(kas_id)))).scalar_one()
    assert row.dibuat_oleh == kasir.id


async def test_push_pengguna_dari_toko_lain_tetap_disimpan_tapi_ditandai_audit_log(
    client: AsyncClient, db_session: AsyncSession, toko_a, toko_b
) -> None:
    """Desain #5: operasi SUDAH TERJADI di toko (barang sudah keluar) -
    data tetap disimpan walau identitas pengguna_id-nya tidak valid (di
    sini: milik toko B, dipakai push ke toko A) - TIDAK ditolak, tapi
    ditandai di audit_log + notifikasi owner."""
    produk = await buat_produk(db_session, toko_a.toko.id)
    metode = await buat_metode_bayar(db_session, toko_a.toko.id)
    perangkat = await buat_perangkat(db_session, toko_a.toko.id, toko_a.outlet.id)
    transaksi_id = str(uuid.uuid4())

    resp = await client.post(
        "/sync/push",
        headers=toko_a.headers,
        json={
            "perangkat_id": str(perangkat.id),
            "transaksi": [
                {
                    "id": transaksi_id, "outlet_id": str(toko_a.outlet.id),
                    "nomor_struk": "OUT1-ID-0002", "tanggal": datetime.now(UTC).isoformat(),
                    "items": [
                        {"produk_id": str(produk.id), "nama_produk": produk.nama, "qty": "1", "harga_satuan": "15000"}
                    ],
                    "metode_bayar_id": str(metode.id), "total_bayar": "15000",
                    "pengguna_id": str(toko_b.pengguna.id),
                }
            ],
        },
    )
    assert resp.status_code == 200
    assert resp.json()["transaksi"][0]["status"] == "diterima"

    row = (await db_session.execute(select(Transaksi).where(Transaksi.id == uuid.UUID(transaksi_id)))).scalar_one()
    assert row is not None  # tetap tersimpan, tidak ditolak

    audit = (
        await db_session.execute(
            select(AuditLog).where(AuditLog.aksi == "anomali_identitas", AuditLog.record_id == row.id)
        )
    ).scalar_one()
    assert audit.data_baru["alasan"] == ["pengguna_bukan_milik_toko"]

    notif = (
        await db_session.execute(select(Notifikasi).where(Notifikasi.toko_id == toko_a.toko.id))
    ).scalar_one()
    assert notif.jenis == "anomali_identitas"


async def test_push_pengguna_nonaktif_ditandai_di_audit_log(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    kasir_nonaktif = await _buat_kasir(db_session, toko_a.toko.id, toko_a.outlet.id, aktif=False)
    produk = await buat_produk(db_session, toko_a.toko.id)
    metode = await buat_metode_bayar(db_session, toko_a.toko.id)
    perangkat = await buat_perangkat(db_session, toko_a.toko.id, toko_a.outlet.id)
    transaksi_id = str(uuid.uuid4())

    resp = await client.post(
        "/sync/push",
        headers=toko_a.headers,
        json={
            "perangkat_id": str(perangkat.id),
            "transaksi": [
                {
                    "id": transaksi_id, "outlet_id": str(toko_a.outlet.id),
                    "nomor_struk": "OUT1-ID-0003", "tanggal": datetime.now(UTC).isoformat(),
                    "items": [
                        {"produk_id": str(produk.id), "nama_produk": produk.nama, "qty": "1", "harga_satuan": "15000"}
                    ],
                    "metode_bayar_id": str(metode.id), "total_bayar": "15000",
                    "pengguna_id": str(kasir_nonaktif.id),
                }
            ],
        },
    )
    assert resp.status_code == 200
    row_id = uuid.UUID(transaksi_id)
    audit = (
        await db_session.execute(
            select(AuditLog).where(AuditLog.aksi == "anomali_identitas", AuditLog.record_id == row_id)
        )
    ).scalar_one()
    assert audit.data_baru["alasan"] == ["pengguna_nonaktif"]


async def test_push_kasir_tanpa_akses_outlet_ditandai_di_audit_log(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    # Kasir TANPA baris akses_outlet sama sekali (beda outlet dari toko_a.outlet).
    kasir_tanpa_akses = await _buat_kasir(db_session, toko_a.toko.id, outlet_id=None)
    produk = await buat_produk(db_session, toko_a.toko.id)
    metode = await buat_metode_bayar(db_session, toko_a.toko.id)
    perangkat = await buat_perangkat(db_session, toko_a.toko.id, toko_a.outlet.id)
    transaksi_id = str(uuid.uuid4())

    resp = await client.post(
        "/sync/push",
        headers=toko_a.headers,
        json={
            "perangkat_id": str(perangkat.id),
            "transaksi": [
                {
                    "id": transaksi_id, "outlet_id": str(toko_a.outlet.id),
                    "nomor_struk": "OUT1-ID-0004", "tanggal": datetime.now(UTC).isoformat(),
                    "items": [
                        {"produk_id": str(produk.id), "nama_produk": produk.nama, "qty": "1", "harga_satuan": "15000"}
                    ],
                    "metode_bayar_id": str(metode.id), "total_bayar": "15000",
                    "pengguna_id": str(kasir_tanpa_akses.id),
                }
            ],
        },
    )
    assert resp.status_code == 200
    row_id = uuid.UUID(transaksi_id)
    audit = (
        await db_session.execute(
            select(AuditLog).where(AuditLog.aksi == "anomali_identitas", AuditLog.record_id == row_id)
        )
    ).scalar_one()
    assert "tidak_punya_akses_outlet" in audit.data_baru["alasan"]


async def test_pin_login_online_sukses_menghasilkan_token_atas_nama_karyawan(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    kasir = await _buat_kasir(db_session, toko_a.toko.id, toko_a.outlet.id, pin="654321")
    perangkat = await buat_perangkat(db_session, toko_a.toko.id, toko_a.outlet.id)

    resp = await client.post(
        "/auth/pin-login",
        json={"perangkat_id": str(perangkat.id), "pengguna_id": str(kasir.id), "pin": "654321"},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["pengguna"]["id"] == str(kasir.id)
    assert body["pengguna"]["nama"] == "Kasir Budi"


async def test_pin_login_online_pin_salah_ditolak(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    kasir = await _buat_kasir(db_session, toko_a.toko.id, toko_a.outlet.id, pin="111111")
    perangkat = await buat_perangkat(db_session, toko_a.toko.id, toko_a.outlet.id)

    resp = await client.post(
        "/auth/pin-login",
        json={"perangkat_id": str(perangkat.id), "pengguna_id": str(kasir.id), "pin": "999999"},
    )
    assert resp.status_code == 401


async def test_pin_login_online_karyawan_nonaktif_ditolak(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    kasir = await _buat_kasir(db_session, toko_a.toko.id, toko_a.outlet.id, pin="222222", aktif=False)
    perangkat = await buat_perangkat(db_session, toko_a.toko.id, toko_a.outlet.id)

    resp = await client.post(
        "/auth/pin-login",
        json={"perangkat_id": str(perangkat.id), "pengguna_id": str(kasir.id), "pin": "222222"},
    )
    assert resp.status_code == 401


async def test_pin_login_online_kasir_tanpa_akses_outlet_ditolak(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    kasir_tanpa_akses = await _buat_kasir(db_session, toko_a.toko.id, outlet_id=None, pin="333333")
    perangkat = await buat_perangkat(db_session, toko_a.toko.id, toko_a.outlet.id)

    resp = await client.post(
        "/auth/pin-login",
        json={"perangkat_id": str(perangkat.id), "pengguna_id": str(kasir_tanpa_akses.id), "pin": "333333"},
    )
    assert resp.status_code == 403


async def test_kasir_token_karyawan_tanpa_izin_refund_ditolak_403(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    """Desain #6 - online langsung (refund) pakai token KARYAWAN (bukan
    token Owner/device), izin dicek berdasarkan role token itu sendiri."""
    kasir = await _buat_kasir(db_session, toko_a.toko.id, toko_a.outlet.id, pin="444444")
    perangkat = await buat_perangkat(db_session, toko_a.toko.id, toko_a.outlet.id)

    login = await client.post(
        "/auth/pin-login",
        json={"perangkat_id": str(perangkat.id), "pengguna_id": str(kasir.id), "pin": "444444"},
    )
    assert login.status_code == 200
    token_kasir = login.json()["access_token"]

    produk = await buat_produk(db_session, toko_a.toko.id, harga_jual=Decimal("15000"))
    metode = await buat_metode_bayar(db_session, toko_a.toko.id)
    checkout = await client.post(
        "/transaksi",
        headers=toko_a.headers,
        json={
            "outlet_id": str(toko_a.outlet.id),
            "nomor_struk": "OUT1-ID-REFUND",
            "tanggal": datetime.now(UTC).isoformat(),
            "items": [{"produk_id": str(produk.id), "nama_produk": produk.nama, "qty": "1", "harga_satuan": "15000"}],
            "metode_bayar_id": str(metode.id),
            "total_bayar": "15000",
        },
    )
    assert checkout.status_code == 201
    transaksi_id = checkout.json()["id"]

    resp = await client.post(
        f"/transaksi/{transaksi_id}/refund",
        headers={"Authorization": f"Bearer {token_kasir}"},
        json={"alasan": "barang rusak", "items": []},
    )
    assert resp.status_code == 403


async def test_kuota_maks_pengguna_menghitung_semua_karyawan(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    paket_bisnis = (await db_session.execute(select(Paket).where(Paket.nama == "Bisnis"))).scalar_one()
    paket_bisnis.maks_pengguna = 3
    await db_session.commit()

    # Owner (1) sudah ada dari buat_toko_siap_pakai - tambah 2 karyawan lagi
    # lewat endpoint (total 3) harus SUKSES, karyawan ke-4 harus ditolak.
    for nama in ["Kasir A", "Kasir B"]:
        resp = await client.post(
            "/pengguna", headers=toko.headers, json={"role_id": str(toko.role.id), "nama": nama, "outlet_ids": []},
        )
        assert resp.status_code == 201, resp.text

    resp4 = await client.post(
        "/pengguna", headers=toko.headers, json={"role_id": str(toko.role.id), "nama": "Kasir C", "outlet_ids": []},
    )
    assert resp4.status_code == 403
    assert resp4.json()["detail"] == {"kode": "kuota_habis", "jenis": "pengguna", "batas": 3}


async def test_sync_pull_mengirim_pengguna_dgn_pin_hash_dan_role_izin(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    kasir = await _buat_kasir(db_session, toko_a.toko.id, toko_a.outlet.id, pin="777777")
    perangkat = await buat_perangkat(db_session, toko_a.toko.id, toko_a.outlet.id)

    resp = await client.get(
        "/sync/pull",
        headers=toko_a.headers,
        params={
            "perangkat_id": str(perangkat.id),
            "since": "1970-01-01T00:00:00Z",
            "outlet_id": str(toko_a.outlet.id),
        },
    )
    assert resp.status_code == 200
    body = resp.json()
    pengguna_rows = {p["id"]: p for p in body["pengguna"]}
    assert str(kasir.id) in pengguna_rows
    assert pengguna_rows[str(kasir.id)]["pin_hash"] is not None
    assert pengguna_rows[str(kasir.id)]["pin_hash"] != "777777"  # bukan PIN mentah

    role_izin_untuk_kasir = [r for r in body["role_izin"] if r["role_id"] == str(kasir.role_id)]
    assert any(r["izin_kode"] == "transaksi.buat" for r in role_izin_untuk_kasir)
    assert not any(r["izin_kode"] == "transaksi.refund" for r in role_izin_untuk_kasir)


async def test_sync_pull_tidak_mengirim_kasir_outlet_lain_tanpa_akses(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    from app.models.outlet import Outlet

    outlet_lain = Outlet(toko_id=toko_a.toko.id, kode="OUT2", nama="Outlet Cabang")
    db_session.add(outlet_lain)
    await db_session.commit()
    await db_session.refresh(outlet_lain)

    kasir_outlet_lain = await _buat_kasir(db_session, toko_a.toko.id, outlet_lain.id, nama="Kasir Cabang")
    perangkat = await buat_perangkat(db_session, toko_a.toko.id, toko_a.outlet.id)

    resp = await client.get(
        "/sync/pull",
        headers=toko_a.headers,
        params={
            "perangkat_id": str(perangkat.id),
            "since": "1970-01-01T00:00:00Z",
            "outlet_id": str(toko_a.outlet.id),
        },
    )
    assert resp.status_code == 200
    pengguna_ids = {p["id"] for p in resp.json()["pengguna"]}
    assert str(kasir_outlet_lain.id) not in pengguna_ids
