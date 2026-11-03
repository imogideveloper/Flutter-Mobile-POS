from datetime import UTC, datetime
from decimal import Decimal

from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.stok import Stok
from app.models.transaksi import ItemTransaksi, ItemTransaksiModifier
from tests.conftest import buat_metode_bayar, buat_produk, buat_toko_siap_pakai


async def test_checkout_produk_pakai_resep_memotong_stok_bahan_baku(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    # resep adalah fitur tingkat 1 (Pro) - pakai toko Bisnis di sini (bukan
    # toko_a default Gratis) krn tes ini soal mekanika potong stok, bukan
    # soal gating-nya sendiri (lihat tests/test_gating_fitur.py utk itu).
    toko_a = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    gula_aren = await buat_produk(db_session, toko_a.toko.id, nama="Gula Aren (bahan)", harga_jual=Decimal("0"))
    susu = await buat_produk(db_session, toko_a.toko.id, nama="Susu (bahan)", harga_jual=Decimal("0"))

    kopi_susu = await buat_produk(db_session, toko_a.toko.id, nama="Kopi Susu Gula Aren", harga_jual=Decimal("23000"))
    kopi_susu.pakai_resep = True
    await db_session.commit()

    await client.post(
        f"/produk/{kopi_susu.id}/resep", headers=toko_a.headers, json={"bahan_id": str(gula_aren.id), "qty": "0.05"}
    )
    await client.post(
        f"/produk/{kopi_susu.id}/resep", headers=toko_a.headers, json={"bahan_id": str(susu.id), "qty": "0.1"}
    )

    metode = await buat_metode_bayar(db_session, toko_a.toko.id)
    resp = await client.post(
        "/transaksi",
        headers=toko_a.headers,
        json={
            "outlet_id": str(toko_a.outlet.id),
            "nomor_struk": "OUT1-RES001",
            "tanggal": datetime.now(UTC).isoformat(),
            "items": [
                {
                    "produk_id": str(kopi_susu.id),
                    "nama_produk": kopi_susu.nama,
                    "qty": "2",
                    "harga_satuan": "23000",
                }
            ],
            "metode_bayar_id": str(metode.id),
            "total_bayar": "46000",
        },
    )
    assert resp.status_code == 201

    # Produk jadi (Kopi Susu Gula Aren) TIDAK boleh punya baris stok sendiri.
    stok_kopi = (await db_session.execute(select(Stok).where(Stok.produk_id == kopi_susu.id))).scalar_one_or_none()
    assert stok_kopi is None

    # Bahan baku dipotong proporsional: qty 2 x resep 0.05 = 0.1 gula aren, 2 x 0.1 = 0.2 susu.
    stok_gula = (await db_session.execute(select(Stok).where(Stok.produk_id == gula_aren.id))).scalar_one()
    assert stok_gula.jumlah == Decimal("-0.1")

    stok_susu = (await db_session.execute(select(Stok).where(Stok.produk_id == susu.id))).scalar_one()
    assert stok_susu.jumlah == Decimal("-0.2")


async def test_checkout_tanpa_pakai_resep_tetap_motong_stok_produk_sendiri(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id, harga_jual=Decimal("15000"))
    metode = await buat_metode_bayar(db_session, toko_a.toko.id)

    await client.post(
        "/transaksi",
        headers=toko_a.headers,
        json={
            "outlet_id": str(toko_a.outlet.id),
            "nomor_struk": "OUT1-RES002",
            "tanggal": datetime.now(UTC).isoformat(),
            "items": [
                {"produk_id": str(produk.id), "nama_produk": produk.nama, "qty": "1", "harga_satuan": "15000"}
            ],
            "metode_bayar_id": str(metode.id),
            "total_bayar": "15000",
        },
    )

    stok = (await db_session.execute(select(Stok).where(Stok.produk_id == produk.id))).scalar_one()
    assert stok.jumlah == Decimal("-1")


async def test_checkout_online_menambah_harga_modifier_ad_hoc_di_atas_harga_database(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    # Tahap 3a D.1: checkout ONLINE mengabaikan harga_satuan dari body
    # sepenuhnya - harga dasar SELALU dari Produk.harga_jual di database.
    # Modifier tanpa modifier_id (ad-hoc, tidak ada di katalog) tetap
    # dipercaya dari body (tidak ada sumber lain utk validasi - gap yang
    # didokumentasikan), DITAMBAHKAN di atas harga database, BUKAN
    # dianggap "sudah termasuk" di harga_satuan body seperti sebelumnya.
    produk = await buat_produk(db_session, toko_a.toko.id, nama="Kopi Susu Gula Aren", harga_jual=Decimal("25000"))
    metode = await buat_metode_bayar(db_session, toko_a.toko.id)

    resp = await client.post(
        "/transaksi",
        headers=toko_a.headers,
        json={
            "outlet_id": str(toko_a.outlet.id),
            "nomor_struk": "OUT1-MOD001",
            "tanggal": datetime.now(UTC).isoformat(),
            "items": [
                {
                    "produk_id": str(produk.id),
                    "nama_produk": produk.nama,
                    "qty": "1",
                    "harga_satuan": "999999",  # diabaikan server - dicoba dipalsukan tinggi tapi tidak berpengaruh
                    "modifiers": [{"nama": "Extra shot", "harga": "2000"}, {"nama": "Less sugar", "harga": "0"}],
                }
            ],
            "metode_bayar_id": str(metode.id),
            "total_bayar": "27000",
        },
    )
    assert resp.status_code == 201
    assert resp.json()["subtotal"] == "27000.00"  # 25000 (DB) + 2000 (modifier ad-hoc) + 0

    item = (await db_session.execute(select(ItemTransaksi))).scalars().one()
    assert item.harga_satuan == Decimal("27000")
    modifier_rows = (
        await db_session.execute(
            select(ItemTransaksiModifier).where(ItemTransaksiModifier.item_transaksi_id == item.id)
        )
    ).scalars().all()
    assert len(modifier_rows) == 2
    nama_modifier = {m.nama for m in modifier_rows}
    assert nama_modifier == {"Extra shot", "Less sugar"}
