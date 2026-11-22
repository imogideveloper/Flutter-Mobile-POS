"""IMOGI no. 6: tipe pesanan bawaan dan biaya layanan 5% hanya untuk makan di
tempat (Kafe, Restoran), dibuat saat daftar dan ikut sync pull."""

import uuid
from datetime import UTC, datetime

import pytest
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.otp_store import InMemoryOtpStore
from app.models.akun import Pengguna
from app.models.order import TipeOrder, TipeOrderPajak
from app.models.outlet import PengaturanOutlet
from app.models.promo import Pajak
from tests.conftest import buat_toko_siap_pakai


async def _daftar(client: AsyncClient, otp_store: InMemoryOtpStore, no_hp: str, jenis: str) -> dict:
    await otp_store.simpan(no_hp, "123456", 300)
    resp = await client.post(
        "/auth/otp/verify",
        json={
            "no_hp": no_hp,
            "kode": "123456",
            "device_uid": f"dev-{no_hp}",
            "nama_perangkat": "HP",
            "nama_toko": f"Toko {jenis}",
            "nama_pemilik": "Pemilik",
            "jenis_usaha": jenis,
            "pin": "482913",
        },
    )
    assert resp.status_code == 200, resp.text
    return resp.json()


@pytest.mark.parametrize("jenis", ["CAF", "RES"])
async def test_kafe_dan_restoran_mendapat_service_5_persen_hanya_untuk_makan_di_tempat(
    client: AsyncClient, db_session: AsyncSession, otp_store: InMemoryOtpStore, jenis: str
) -> None:
    body = await _daftar(client, otp_store, "0813" + ("1" if jenis == "CAF" else "2") * 8, jenis)
    toko_id = uuid.UUID(body["toko"]["id"])

    tipe = {
        t.nama: t
        for t in (await db_session.execute(select(TipeOrder).where(TipeOrder.toko_id == toko_id))).scalars().all()
    }
    assert set(tipe) == {"Makan di tempat", "Bawa pulang", "Delivery"}
    assert tipe["Makan di tempat"].kanal == "makan_di_tempat" and tipe["Makan di tempat"].pakai_meja is True
    assert tipe["Bawa pulang"].kanal == "bawa_pulang"
    assert tipe["Delivery"].kanal == "antar"

    service = (
        await db_session.execute(select(Pajak).where(Pajak.toko_id == toko_id, Pajak.tipe == "service"))
    ).scalar_one()
    assert service.tipe == "service" and float(service.persen) == 5 and service.aktif is True
    assert service.termasuk_harga is False

    tautan = (await db_session.execute(select(TipeOrderPajak))).scalars().all()
    assert [(t.tipe_order_id, t.pajak_id) for t in tautan] == [(tipe["Makan di tempat"].id, service.id)], (
        "service hanya ditautkan ke Makan di tempat, bukan Bawa pulang/Delivery"
    )


@pytest.mark.parametrize("jenis", ["CAT", "BRD", "FRZ", "BEV", "STL"])
async def test_jenis_usaha_lain_dapat_tipe_pesanan_tanpa_service_bawaan(
    client: AsyncClient, db_session: AsyncSession, otp_store: InMemoryOtpStore, jenis: str
) -> None:
    angka = {"CAT": "3", "BRD": "4", "FRZ": "5", "BEV": "6", "STL": "7"}[jenis]
    body = await _daftar(client, otp_store, "0813" + angka * 8, jenis)
    toko_id = uuid.UUID(body["toko"]["id"])

    jumlah_tipe = len((await db_session.execute(select(TipeOrder).where(TipeOrder.toko_id == toko_id))).scalars().all())
    assert jumlah_tipe == 3
    semua = (await db_session.execute(select(Pajak).where(Pajak.toko_id == toko_id))).scalars().all()
    assert [p for p in semua if p.tipe == "service"] == []


@pytest.mark.parametrize(
    ("jenis", "angka", "ada_pb1"),
    [("CAF", "1", True), ("RES", "2", True), ("CAT", "3", True), ("BRD", "4", True), ("FRZ", "5", False),
     ("BEV", "6", True), ("STL", "7", True)],
)
async def test_pb1_dan_pesan_penutup_struk_bawaan_per_jenis_usaha(
    client: AsyncClient, db_session: AsyncSession, otp_store: InMemoryOtpStore, jenis: str, angka: str, ada_pb1: bool
) -> None:
    body = await _daftar(client, otp_store, "0814" + angka * 8, jenis)
    toko_id = uuid.UUID(body["toko"]["id"])

    pb1 = (
        await db_session.execute(select(Pajak).where(Pajak.toko_id == toko_id, Pajak.nama == "PB1"))
    ).scalars().all()
    if ada_pb1:
        assert len(pb1) == 1
        assert pb1[0].tipe == "pajak" and float(pb1[0].persen) == 10 and pb1[0].termasuk_harga is False
    else:
        assert pb1 == []

    pengaturan = (await db_session.execute(select(PengaturanOutlet))).scalars().all()
    assert any(p.footer_struk == "Terima kasih, selamat menikmati!" for p in pengaturan)
    # Nilai yang dikunci paket tidak dinyalakan otomatis.
    assert all(p.struk_ringkas is False and p.pakai_nomor_antrean is False for p in pengaturan)


async def test_tipe_pesanan_ikut_sync_pull(
    client: AsyncClient, db_session: AsyncSession, otp_store: InMemoryOtpStore
) -> None:
    body = await _daftar(client, otp_store, "08139999999", "CAF")
    headers = {"Authorization": f"Bearer {body['access_token']}"}

    resp = await client.get(
        "/sync/pull",
        headers=headers,
        params={"since": datetime(1970, 1, 1, tzinfo=UTC).isoformat(), "perangkat_id": body["perangkat_id"]},
    )
    assert resp.status_code == 200, resp.text
    hasil = resp.json()
    assert {t["nama"] for t in hasil["tipe_order"]} == {"Makan di tempat", "Bawa pulang", "Delivery"}
    makan = next(t for t in hasil["tipe_order"] if t["nama"] == "Makan di tempat")
    assert makan["kanal"] == "makan_di_tempat" and makan["pakai_meja"] is True and makan["aktif"] is True
    assert {p["nama"] for p in hasil["pajak"]} == {"Service Charge", "PB1"}
    assert [t["tipe_order_id"] for t in hasil["tipe_order_pajak"]] == [makan["id"]]


async def test_toko_lama_tanpa_bawaan_tidak_terpengaruh(client: AsyncClient, db_session: AsyncSession) -> None:
    """Toko yang dibuat tanpa jalur pendaftaran (mis. fixture) tidak mendapat tipe pesanan otomatis."""
    toko = await buat_toko_siap_pakai(db_session)
    assert (await db_session.execute(select(TipeOrder).where(TipeOrder.toko_id == toko.toko.id))).scalars().all() == []
    assert (await db_session.execute(select(Pengguna).where(Pengguna.toko_id == toko.toko.id))).scalars().all()


async def test_peran_bawaan_kru_ada_dengan_izin_sempit(db_session: AsyncSession) -> None:
    """Peran sistem "Barista & Dapur" dan "Gudang" tersedia untuk semua toko (seed sama dengan migrasi 0028)."""
    from app.models.akun import Izin, Role, RoleIzin

    async def izin(nama: str) -> set[str]:
        role = (await db_session.execute(select(Role).where(Role.nama == nama, Role.is_system.is_(True)))).scalar_one()
        rows = await db_session.execute(
            select(Izin.kode).join(RoleIzin, RoleIzin.izin_id == Izin.id).where(RoleIzin.role_id == role.id)
        )
        return set(rows.scalars().all())

    assert await izin("Barista & Dapur") == {"transaksi.buat", "pesanan.status"}
    assert await izin("Gudang") == {"stok.kelola", "pembelian.kelola", "stok.opname_posting"}


@pytest.mark.asyncio
async def test_izin_panduan_imogi_ada_dan_peran_bawaan_sesuai(db_session: AsyncSession) -> None:
    """8 izin tambahan dari panduan IMOGI ada di katalog; Kasir dapat izin bon/status pesanan, bukan laba rugi."""
    from app.models.akun import Izin, Role, RoleIzin

    baru = {
        "bon.jual", "bon.lihat", "pesanan.status", "persetujuan.pin",
        "produk.lihat_margin", "stok.opname_posting", "pengeluaran.catat", "laporan.keuangan",
    }
    kode = set((await db_session.execute(select(Izin.kode))).scalars().all())
    assert baru <= kode

    async def izin(nama: str) -> set[str]:
        role = (await db_session.execute(select(Role).where(Role.nama == nama, Role.is_system.is_(True)))).scalar_one()
        rows = await db_session.execute(
            select(Izin.kode).join(RoleIzin, RoleIzin.izin_id == Izin.id).where(RoleIzin.role_id == role.id)
        )
        return set(rows.scalars().all())

    kasir = await izin("Kasir")
    assert {"bon.jual", "bon.lihat", "pesanan.status"} <= kasir
    assert "laporan.keuangan" not in kasir
    assert baru <= await izin("Owner")
    assert "pengeluaran.catat" in await izin("Manajer")
