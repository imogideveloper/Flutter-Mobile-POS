"""Hak akses outlet (tahap 2 bagian A) - SATU TINGKAT LEBIH SEMPIT dari
kepemilikan toko (lihat app/services/kepemilikan.py, yg sudah dites di
tests/test_isolasi_toko.py). Di sini: Kasir yang cuma punya akses_outlet
ke outlet A WAJIB ditolak 403 kalau mencoba pakai outlet B (TOKO YANG
SAMA) - beda dari isolasi-antar-toko yang hasilnya 404. Owner/Manajer
WAJIB tetap bisa pakai outlet mana pun di tokonya."""

import uuid
from dataclasses import dataclass
from datetime import UTC, date, datetime

from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import create_access_token
from app.models.akun import AksesOutlet, Pengguna, Role
from app.models.outlet import Outlet
from tests.conftest import buat_metode_bayar, buat_perangkat, buat_produk, buat_toko_siap_pakai


@dataclass
class _Sesi:
    pengguna_id: uuid.UUID
    token: str

    @property
    def headers(self) -> dict[str, str]:
        return {"Authorization": f"Bearer {self.token}"}


async def _buat_pengguna(
    db: AsyncSession, *, toko_id: uuid.UUID, nama_role: str, outlet_ids: list[uuid.UUID], nama: str
) -> _Sesi:
    role = (
        await db.execute(select(Role).where(Role.nama == nama_role, Role.is_system.is_(True)))
    ).scalar_one()
    pengguna = Pengguna(toko_id=toko_id, role_id=role.id, nama=nama)
    db.add(pengguna)
    await db.flush()
    for outlet_id in outlet_ids:
        db.add(AksesOutlet(pengguna_id=pengguna.id, outlet_id=outlet_id))
    await db.commit()
    token = create_access_token(pengguna_id=pengguna.id, toko_id=toko_id, role_id=role.id)
    return _Sesi(pengguna_id=pengguna.id, token=token)


async def _siapkan(db: AsyncSession, *, nama_paket: str = "Bisnis"):
    """Satu toko, DUA outlet, Kasir yg cuma punya akses ke outlet A, dan
    Owner (selalu akses semua outlet di tokonya)."""

    toko = await buat_toko_siap_pakai(db, nama_paket=nama_paket, jumlah_outlet=5)
    outlet_a = toko.outlet
    outlet_b = Outlet(toko_id=toko.toko.id, kode="OUT2", nama="Outlet B")
    db.add(outlet_b)
    await db.commit()
    await db.refresh(outlet_b)

    kasir = await _buat_pengguna(
        db, toko_id=toko.toko.id, nama_role="Kasir", outlet_ids=[outlet_a.id], nama="Kasir Outlet A"
    )
    owner = _Sesi(pengguna_id=toko.pengguna.id, token=toko.token)
    return toko, outlet_a, outlet_b, kasir, owner


async def test_kasir_checkout_outlet_sendiri_diterima(client: AsyncClient, db_session: AsyncSession) -> None:
    toko, outlet_a, outlet_b, kasir, owner = await _siapkan(db_session)
    produk = await buat_produk(db_session, toko.toko.id)
    metode = await buat_metode_bayar(db_session, toko.toko.id)

    resp = await client.post(
        "/transaksi",
        headers=kasir.headers,
        json={
            "outlet_id": str(outlet_a.id),
            "nomor_struk": "OUTA-AKS001",
            "tanggal": datetime.now(UTC).isoformat(),
            "items": [{"produk_id": str(produk.id), "nama_produk": produk.nama, "qty": "1", "harga_satuan": "15000"}],
            "metode_bayar_id": str(metode.id),
            "total_bayar": "15000",
        },
    )
    assert resp.status_code == 201


async def test_kasir_checkout_outlet_lain_ditolak_403(client: AsyncClient, db_session: AsyncSession) -> None:
    toko, outlet_a, outlet_b, kasir, owner = await _siapkan(db_session)
    produk = await buat_produk(db_session, toko.toko.id)
    metode = await buat_metode_bayar(db_session, toko.toko.id)

    resp = await client.post(
        "/transaksi",
        headers=kasir.headers,
        json={
            "outlet_id": str(outlet_b.id),
            "nomor_struk": "OUTB-AKS001",
            "tanggal": datetime.now(UTC).isoformat(),
            "items": [{"produk_id": str(produk.id), "nama_produk": produk.nama, "qty": "1", "harga_satuan": "15000"}],
            "metode_bayar_id": str(metode.id),
            "total_bayar": "15000",
        },
    )
    assert resp.status_code == 403


async def test_owner_checkout_di_outlet_manapun_diterima(client: AsyncClient, db_session: AsyncSession) -> None:
    toko, outlet_a, outlet_b, kasir, owner = await _siapkan(db_session)
    produk = await buat_produk(db_session, toko.toko.id)
    metode = await buat_metode_bayar(db_session, toko.toko.id)

    for i, outlet in enumerate((outlet_a, outlet_b)):
        resp = await client.post(
            "/transaksi",
            headers=owner.headers,
            json={
                "outlet_id": str(outlet.id),
                "nomor_struk": f"OWNER-AKS00{i}",
                "tanggal": datetime.now(UTC).isoformat(),
                "items": [{"produk_id": str(produk.id), "nama_produk": produk.nama, "qty": "1", "harga_satuan": "15000"}],
                "metode_bayar_id": str(metode.id),
                "total_bayar": "15000",
            },
        )
        assert resp.status_code == 201


async def test_kasir_buka_shift_outlet_lain_ditolak_403(client: AsyncClient, db_session: AsyncSession) -> None:
    toko, outlet_a, outlet_b, kasir, owner = await _siapkan(db_session)

    resp = await client.post("/shift/buka", headers=kasir.headers, json={"outlet_id": str(outlet_b.id), "modal_awal": "0"})
    assert resp.status_code == 403

    resp_ok = await client.post("/shift/buka", headers=kasir.headers, json={"outlet_id": str(outlet_a.id), "modal_awal": "0"})
    assert resp_ok.status_code == 201


async def test_kasir_stok_opname_outlet_lain_ditolak_403(client: AsyncClient, db_session: AsyncSession) -> None:
    toko, outlet_a, outlet_b, kasir, owner = await _siapkan(db_session)
    produk = await buat_produk(db_session, toko.toko.id)

    resp = await client.post(
        "/stok-opname",
        headers=kasir.headers,
        json={
            "outlet_id": str(outlet_b.id), "nomor": "OPN-AKS1", "tanggal": date.today().isoformat(),
            "items": [{"produk_id": str(produk.id), "qty_fisik": "1"}],
        },
    )
    assert resp.status_code == 403


async def test_kasir_transfer_stok_dari_outlet_lain_ditolak_403(client: AsyncClient, db_session: AsyncSession) -> None:
    toko, outlet_a, outlet_b, kasir, owner = await _siapkan(db_session)
    produk = await buat_produk(db_session, toko.toko.id)

    # Kasir cuma punya akses outlet A - transfer dgn outlet ASAL B harus ditolak,
    # walau outlet B tetap sah milik toko yang sama.
    resp = await client.post(
        "/transfer-stok",
        headers=kasir.headers,
        json={
            "dari_outlet_id": str(outlet_b.id), "ke_outlet_id": str(outlet_a.id), "nomor": "TRF-AKS1",
            "items": [{"produk_id": str(produk.id), "qty": "1"}],
        },
    )
    assert resp.status_code == 403


async def test_kasir_pembelian_outlet_lain_ditolak_403(client: AsyncClient, db_session: AsyncSession) -> None:
    toko, outlet_a, outlet_b, kasir, owner = await _siapkan(db_session)
    produk = await buat_produk(db_session, toko.toko.id)

    resp = await client.post(
        "/pembelian",
        headers=kasir.headers,
        json={
            "outlet_id": str(outlet_b.id), "nomor": "PO-AKS1", "tanggal": date.today().isoformat(),
            "items": [{"produk_id": str(produk.id), "qty": "1", "harga_satuan": "1000"}],
        },
    )
    assert resp.status_code == 403


async def test_kasir_laporan_outlet_lain_ditolak_403(client: AsyncClient, db_session: AsyncSession) -> None:
    toko, outlet_a, outlet_b, kasir, owner = await _siapkan(db_session)
    sekarang = datetime.now(UTC)

    resp = await client.get(
        "/laporan/penjualan",
        headers=kasir.headers,
        params={
            "dari": sekarang.isoformat(), "sampai": sekarang.isoformat(), "outlet_id": str(outlet_b.id),
        },
    )
    assert resp.status_code == 403


async def test_kasir_sync_pull_outlet_lain_ditolak_403(client: AsyncClient, db_session: AsyncSession) -> None:
    toko, outlet_a, outlet_b, kasir, owner = await _siapkan(db_session)
    perangkat = await buat_perangkat(db_session, toko.toko.id, outlet_a.id, device_uid="device-kasir-a")

    resp = await client.get(
        "/sync/pull",
        headers=kasir.headers,
        params={"perangkat_id": str(perangkat.id), "since": "1970-01-01T00:00:00Z", "outlet_id": str(outlet_b.id)},
    )
    assert resp.status_code == 403


async def test_kasir_antrean_outlet_lain_ditolak_403(client: AsyncClient, db_session: AsyncSession) -> None:
    toko, outlet_a, outlet_b, kasir, owner = await _siapkan(db_session)
    perangkat = await buat_perangkat(db_session, toko.toko.id, outlet_a.id, device_uid="device-kasir-a2")

    resp = await client.post(
        "/antrean/nomor",
        headers=kasir.headers,
        params={"outlet_id": str(outlet_b.id), "perangkat_id": str(perangkat.id)},
    )
    assert resp.status_code == 403


async def test_kasir_dapur_pesanan_outlet_lain_ditolak_403(client: AsyncClient, db_session: AsyncSession) -> None:
    toko, outlet_a, outlet_b, kasir, owner = await _siapkan(db_session)

    resp = await client.get("/dapur/pesanan", headers=kasir.headers, params={"outlet_id": str(outlet_b.id)})
    assert resp.status_code == 403


async def test_kasir_meja_outlet_lain_ditolak_403(client: AsyncClient, db_session: AsyncSession) -> None:
    toko, outlet_a, outlet_b, kasir, owner = await _siapkan(db_session)

    resp = await client.post(f"/outlets/{outlet_b.id}/meja", headers=kasir.headers, json={"nama": "Meja 1"})
    assert resp.status_code == 403
