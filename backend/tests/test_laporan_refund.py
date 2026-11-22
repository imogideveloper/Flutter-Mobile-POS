"""Laporan dan laba rugi setelah refund (keputusan sementara AT1, docs/perlu_konfirmasi.md).

Penjualan = transaksi selesai + refund sebagian, dikurangi refund. Refund penuh tidak ikut. HPP hanya
dikurangi untuk barang yang dikembalikan ke stok."""

import uuid
from datetime import UTC, datetime, timedelta
from decimal import Decimal
from types import SimpleNamespace

from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.produk import Produk
from app.models.transaksi import ItemTransaksi
from app.services.laporan_service import PenjualanTransaksi
from tests.conftest import buat_metode_bayar, buat_toko_siap_pakai


async def _jual_empat(client: AsyncClient, db: AsyncSession, toko) -> tuple[str, str, datetime]:
    """4 x Kopi @15.000 (HPP 6.000) = 60.000 tanpa pajak. Mengembalikan (transaksi_id, item_id, sekarang)."""
    produk = Produk(toko_id=toko.toko.id, nama="Kopi Susu", harga_jual=Decimal("15000"), hpp=Decimal("6000"))
    db.add(produk)
    await db.commit()
    await db.refresh(produk)
    metode = await buat_metode_bayar(db, toko.toko.id)
    sekarang = datetime.now(UTC)
    resp = await client.post(
        "/transaksi",
        headers=toko.headers,
        json={
            "outlet_id": str(toko.outlet.id),
            "nomor_struk": "OUT1-RF1",
            "tanggal": sekarang.isoformat(),
            "items": [
                {
                    "produk_id": str(produk.id),
                    "nama_produk": produk.nama,
                    "qty": "4",
                    "harga_satuan": "15000",
                    "hpp_satuan": "6000",
                }
            ],
            "metode_bayar_id": str(metode.id),
            "total_bayar": "60000",
        },
    )
    assert resp.status_code == 201, resp.text
    transaksi_id = resp.json()["id"]
    item = (
        await db.execute(select(ItemTransaksi).where(ItemTransaksi.transaksi_id == uuid.UUID(transaksi_id)))
    ).scalars().first()
    return transaksi_id, str(item.id), sekarang


async def _refund(client: AsyncClient, toko, transaksi_id: str, item_id: str, qty: str, *, stok: bool = True) -> dict:
    resp = await client.post(
        f"/transaksi/{transaksi_id}/refund",
        headers=toko.headers,
        json={"alasan": "uji", "kembalikan_stok": stok, "items": [{"item_transaksi_id": item_id, "qty": qty}]},
    )
    assert resp.status_code == 201, resp.text
    return resp.json()


def _rentang(sekarang: datetime) -> dict:
    return {
        "dari": (sekarang - timedelta(days=1)).isoformat(),
        "sampai": (sekarang + timedelta(days=1)).isoformat(),
    }


async def test_refund_sebagian_mengurangi_penjualan_laba_dan_produk_terlaris(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    transaksi_id, item_id, sekarang = await _jual_empat(client, db_session, toko)
    body = await _refund(client, toko, transaksi_id, item_id, "2")
    assert body["status_transaksi"] == "refund_sebagian"

    ringkasan = (await client.get("/laporan/penjualan", headers=toko.headers, params=_rentang(sekarang))).json()
    assert Decimal(ringkasan["penjualan_bersih"]) == Decimal("30000")
    assert Decimal(ringkasan["pajak_service"]) == Decimal("0")
    assert Decimal(ringkasan["total_penerimaan"]) == Decimal("30000")
    assert ringkasan["jumlah_transaksi"] == 1, "refund sebagian: sisanya masih penjualan"
    assert Decimal(ringkasan["laba_kotor"]) == Decimal("18000"), "15.000x2 dikurangi HPP 6.000x2 (stok kembali)"
    assert Decimal(ringkasan["jam_ramai"][0]["total"]) == Decimal("30000")

    terlaris = (await client.get("/laporan/produk-terlaris", headers=toko.headers, params=_rentang(sekarang))).json()
    assert Decimal(terlaris[0]["qty"]) == Decimal("2")
    assert Decimal(terlaris[0]["total"]) == Decimal("30000")

    laba_rugi = (await client.get("/laporan/laba-rugi", headers=toko.headers, params=_rentang(sekarang))).json()
    assert Decimal(laba_rugi["penjualan_kotor"]) == Decimal("30000")
    assert Decimal(laba_rugi["penjualan_bersih"]) == Decimal("30000")
    assert Decimal(laba_rugi["hpp"]) == Decimal("12000")
    assert Decimal(laba_rugi["laba_kotor"]) == Decimal("18000")
    assert laba_rugi["jumlah_transaksi"] == 1


async def test_refund_tanpa_kembali_stok_hpp_tetap_ditanggung(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    transaksi_id, item_id, sekarang = await _jual_empat(client, db_session, toko)
    await _refund(client, toko, transaksi_id, item_id, "1", stok=False)

    laba_rugi = (await client.get("/laporan/laba-rugi", headers=toko.headers, params=_rentang(sekarang))).json()
    assert Decimal(laba_rugi["penjualan_bersih"]) == Decimal("45000")
    assert Decimal(laba_rugi["hpp"]) == Decimal("24000"), "barang yang tidak balik stok tetap jadi biaya"
    assert Decimal(laba_rugi["laba_kotor"]) == Decimal("21000")

    ringkasan = (await client.get("/laporan/penjualan", headers=toko.headers, params=_rentang(sekarang))).json()
    assert Decimal(ringkasan["laba_kotor"]) == Decimal("21000"), "laba kotor ringkasan sama dengan laba rugi"


async def test_refund_penuh_tidak_dihitung_sebagai_penjualan(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    transaksi_id, item_id, sekarang = await _jual_empat(client, db_session, toko)
    body = await _refund(client, toko, transaksi_id, item_id, "4")
    assert body["status_transaksi"] == "refund"

    ringkasan = (await client.get("/laporan/penjualan", headers=toko.headers, params=_rentang(sekarang))).json()
    assert Decimal(ringkasan["penjualan_bersih"]) == Decimal("0")
    assert Decimal(ringkasan["total_penerimaan"]) == Decimal("0")
    assert ringkasan["jumlah_transaksi"] == 0

    terlaris = (await client.get("/laporan/produk-terlaris", headers=toko.headers, params=_rentang(sekarang))).json()
    assert terlaris == []

    laba_rugi = (await client.get("/laporan/laba-rugi", headers=toko.headers, params=_rentang(sekarang))).json()
    assert Decimal(laba_rugi["penjualan_bersih"]) == Decimal("0")
    assert Decimal(laba_rugi["hpp"]) == Decimal("0")
    assert laba_rugi["jumlah_transaksi"] == 0


def test_penjualan_transaksi_membagi_refund_proporsional_ke_pajak_dan_service() -> None:
    """Contoh yang sama dengan uji di HP: Rp18.000 + service/PB1 Rp2.790 = Rp20.790, direfund separuh."""
    t = SimpleNamespace(total=Decimal("20790"), total_pajak=Decimal("2790"), pembulatan=Decimal("0"))

    utuh = PenjualanTransaksi(t, Decimal("0"))
    assert (utuh.penjualan_bersih, utuh.pajak_service, utuh.total_penerimaan) == (
        Decimal("18000.00"),
        Decimal("2790.00"),
        Decimal("20790.00"),
    )

    separuh = PenjualanTransaksi(t, Decimal("10395"))
    assert (separuh.penjualan_bersih, separuh.pajak_service, separuh.total_penerimaan) == (
        Decimal("9000.00"),
        Decimal("1395.00"),
        Decimal("10395.00"),
    )

    lebih = PenjualanTransaksi(t, Decimal("99999"))
    assert (lebih.penjualan_bersih, lebih.pajak_service, lebih.total_penerimaan) == (
        Decimal("0.00"),
        Decimal("0.00"),
        Decimal("0.00"),
    ), "refund melebihi total dibatasi"
