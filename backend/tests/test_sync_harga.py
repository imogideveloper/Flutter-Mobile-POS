"""Tahap 3a Part B - /sync/pull mengirim data yang dibutuhkan
lib/core/harga/kalkulator.dart di HP: harga_outlet, harga_grosir,
tipe_order_pajak, pengaturan_outlet (termasuk pembulatan)."""

from datetime import UTC, datetime, timedelta

from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from sqlalchemy import select

from app.models.order import TipeOrder, TipeOrderPajak
from app.models.outlet import Langganan, Outlet, PengaturanOutlet
from app.models.produk import HargaGrosir, HargaOutlet
from app.models.promo import Pajak
from tests.conftest import buat_perangkat, buat_produk, buat_toko_siap_pakai


async def _pull(client, toko, perangkat, outlet_id=None):
    params = {"since": datetime(1970, 1, 1, tzinfo=UTC).isoformat(), "perangkat_id": str(perangkat.id)}
    if outlet_id is not None:
        params["outlet_id"] = str(outlet_id)
    resp = await client.get("/sync/pull", headers=toko.headers, params=params)
    assert resp.status_code == 200
    return resp.json()


async def test_pull_mengirim_harga_outlet_milik_outlet_device(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id, harga_jual=10000)
    outlet_lain = Outlet(toko_id=toko_a.toko.id, kode="OUT2", nama="Outlet Kedua")
    db_session.add(outlet_lain)
    await db_session.flush()
    db_session.add(HargaOutlet(outlet_id=toko_a.outlet.id, produk_id=produk.id, varian_id=None, harga_jual=9000))
    db_session.add(HargaOutlet(outlet_id=outlet_lain.id, produk_id=produk.id, varian_id=None, harga_jual=8000))
    await db_session.commit()

    perangkat = await buat_perangkat(db_session, toko_a.toko.id, toko_a.outlet.id)
    data = await _pull(client, toko_a, perangkat, outlet_id=toko_a.outlet.id)

    assert len(data["harga_outlet"]) == 1
    assert data["harga_outlet"][0]["harga_jual"] == "9000.00"
    assert data["harga_outlet"][0]["outlet_id"] == str(toko_a.outlet.id)


async def test_pull_mengirim_harga_grosir_umum_dan_outlet_spesifik(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id, harga_jual=10000)
    outlet_lain = Outlet(toko_id=toko_a.toko.id, kode="OUT2", nama="Outlet Kedua")
    db_session.add(outlet_lain)
    await db_session.flush()
    db_session.add(HargaGrosir(produk_id=produk.id, varian_id=None, outlet_id=None, min_qty=10, harga=9000))
    db_session.add(HargaGrosir(produk_id=produk.id, varian_id=None, outlet_id=toko_a.outlet.id, min_qty=10, harga=8500))
    db_session.add(HargaGrosir(produk_id=produk.id, varian_id=None, outlet_id=outlet_lain.id, min_qty=10, harga=8000))
    await db_session.commit()

    perangkat = await buat_perangkat(db_session, toko_a.toko.id, toko_a.outlet.id)
    data = await _pull(client, toko_a, perangkat, outlet_id=toko_a.outlet.id)

    tiers = {t["harga"] for t in data["harga_grosir"]}
    # Tier umum (outlet_id null) + tier khusus outlet device ini - BUKAN
    # tier khusus outlet lain.
    assert tiers == {"9000.00", "8500.00"}


async def test_pull_mengirim_tipe_order_pajak_snapshot_penuh(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    pajak = Pajak(toko_id=toko_a.toko.id, nama="Service", tipe="service", persen=5, urutan=1)
    db_session.add(pajak)
    await db_session.flush()
    tipe_order = TipeOrder(toko_id=toko_a.toko.id, nama="Makan di tempat", markup_persen=0)
    db_session.add(tipe_order)
    await db_session.flush()
    db_session.add(TipeOrderPajak(tipe_order_id=tipe_order.id, pajak_id=pajak.id))
    await db_session.commit()

    perangkat = await buat_perangkat(db_session, toko_a.toko.id, toko_a.outlet.id)
    data = await _pull(client, toko_a, perangkat)

    assert len(data["tipe_order_pajak"]) == 1
    assert data["tipe_order_pajak"][0]["tipe_order_id"] == str(tipe_order.id)
    assert data["tipe_order_pajak"][0]["pajak_id"] == str(pajak.id)

    # Snapshot PENUH tiap pull (tabel tanpa updated_at) - `since` di masa
    # depan TETAP mengembalikan baris yang sama, bukan kosong.
    data2 = await _pull(client, toko_a, perangkat)
    assert len(data2["tipe_order_pajak"]) == 1


async def test_pull_mengirim_pengaturan_outlet_termasuk_pembulatan(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    db_session.add(PengaturanOutlet(outlet_id=toko_a.outlet.id, pembulatan=500))
    await db_session.commit()

    perangkat = await buat_perangkat(db_session, toko_a.toko.id, toko_a.outlet.id)
    data = await _pull(client, toko_a, perangkat, outlet_id=toko_a.outlet.id)

    assert len(data["pengaturan_outlet"]) == 1
    assert data["pengaturan_outlet"][0]["pembulatan"] == 500
    assert data["pengaturan_outlet"][0]["outlet_id"] == str(toko_a.outlet.id)


async def test_pull_tanpa_outlet_id_tidak_mengirim_harga_outlet_atau_pengaturan_outlet(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    perangkat = await buat_perangkat(db_session, toko_a.toko.id, toko_a.outlet.id)
    data = await _pull(client, toko_a, perangkat)

    assert data["harga_outlet"] == []
    assert data["pengaturan_outlet"] == []


async def test_pull_paket_turun_ke_gratis_saat_langganan_kedaluwarsa(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    # Bug yg ditemukan+diperbaiki sambil mengerjakan Part B: sync_service.py
    # masih memanggil paket_aktif_toko (None kalau tidak ada langganan
    # aktif) langsung utk field `paket`, bukan paket_efektif (fallback ke
    # 'Gratis') - padahal /fitur/toko sudah dipindah ke paket_efektif sejak
    # tahap 3a A.3. Device yg langganannya kedaluwarsa akan membaca
    # `paket: null` dari pull walau fitur Gratis-nya sendiri sudah benar.
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    langganan = (await db_session.execute(select(Langganan).where(Langganan.toko_id == toko.toko.id))).scalar_one()
    langganan.berakhir = datetime.now(UTC) - timedelta(days=1)
    await db_session.commit()

    perangkat = await buat_perangkat(db_session, toko.toko.id, toko.outlet.id)
    data = await _pull(client, toko, perangkat)

    assert data["paket"] == "Gratis"
