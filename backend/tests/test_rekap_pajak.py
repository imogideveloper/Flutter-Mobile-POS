import uuid
from datetime import UTC, datetime, timedelta
from decimal import Decimal

from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.promo import Pajak
from app.models.transaksi import Transaksi, TransaksiPajak
from tests.conftest import buat_metode_bayar, buat_produk, buat_toko_siap_pakai


async def _jual(client: AsyncClient, toko, produk, metode, *, qty: str, nomor: str, tanggal: datetime) -> str:
    resp = await client.post(
        "/transaksi",
        headers=toko.headers,
        json={
            "outlet_id": str(toko.outlet.id),
            "nomor_struk": nomor,
            "tanggal": tanggal.isoformat(),
            "items": [
                {"produk_id": str(produk.id), "nama_produk": produk.nama, "qty": qty,
                 "harga_satuan": str(produk.harga_jual)}
            ],
            "metode_bayar_id": str(metode.id),
            "total_bayar": str(Decimal(qty) * produk.harga_jual),
        },
    )
    assert resp.status_code == 201, resp.text
    return resp.json()["id"]


def _rentang(dari: datetime, sampai: datetime) -> dict:
    return {"dari": dari.isoformat(), "sampai": sampai.isoformat()}


async def test_rekap_pajak_mengelompokkan_per_nama_dan_memisahkan_service(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    produk = await buat_produk(db_session, toko.toko.id)
    metode = await buat_metode_bayar(db_session, toko.toko.id)
    pb1 = Pajak(toko_id=toko.toko.id, nama="PB1", tipe="pajak", persen=Decimal("10"), aktif=False)
    service = Pajak(toko_id=toko.toko.id, nama="Service", tipe="service", persen=Decimal("5"), aktif=False)
    db_session.add_all([pb1, service])
    await db_session.commit()

    sekarang = datetime.now(UTC)
    t1 = uuid.UUID(await _jual(client, toko, produk, metode, qty="2", nomor="OUT1-P1", tanggal=sekarang))
    t2 = uuid.UUID(await _jual(client, toko, produk, metode, qty="1", nomor="OUT1-P2", tanggal=sekarang))
    db_session.add_all([
        TransaksiPajak(transaksi_id=t1, pajak_id=pb1.id, nama="PB1", persen=Decimal("10"), jumlah=Decimal("3000")),
        TransaksiPajak(transaksi_id=t1, pajak_id=service.id, nama="Service", persen=Decimal("5"), jumlah=Decimal("1500")),
        TransaksiPajak(transaksi_id=t2, pajak_id=pb1.id, nama="PB1", persen=Decimal("10"), jumlah=Decimal("1500")),
    ])
    await db_session.commit()

    r = await client.get(
        "/laporan/rekap-pajak", headers=toko.headers,
        params=_rentang(sekarang - timedelta(days=1), sekarang + timedelta(days=1)),
    )
    assert r.status_code == 200, r.text
    b = r.json()
    baris = {x["nama"]: x for x in b["baris"]}
    assert Decimal(baris["PB1"]["total"]) == Decimal("4500") and baris["PB1"]["jumlah_transaksi"] == 2
    assert Decimal(baris["Service"]["total"]) == Decimal("1500") and baris["Service"]["tipe"] == "service"
    assert Decimal(b["total_pajak"]) == Decimal("4500")
    assert Decimal(b["total_service"]) == Decimal("1500")
    assert b["jumlah_transaksi"] == 2
    assert b["baris"][0]["nama"] == "PB1"  # terbesar dulu


async def test_rekap_pajak_transaksi_void_tidak_ikut(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    produk = await buat_produk(db_session, toko.toko.id)
    metode = await buat_metode_bayar(db_session, toko.toko.id)
    sekarang = datetime.now(UTC)
    tid = uuid.UUID(await _jual(client, toko, produk, metode, qty="1", nomor="OUT1-V1", tanggal=sekarang))
    db_session.add(TransaksiPajak(transaksi_id=tid, pajak_id=None, nama="PPN", persen=Decimal("11"), jumlah=Decimal("1650")))
    trx = (await db_session.execute(select(Transaksi).where(Transaksi.id == tid))).scalar_one()
    trx.status = "void"
    await db_session.commit()

    b = (await client.get(
        "/laporan/rekap-pajak", headers=toko.headers,
        params=_rentang(sekarang - timedelta(days=1), sekarang + timedelta(days=1)),
    )).json()
    assert b["baris"] == [] and Decimal(b["total_pajak"]) == 0


async def test_pph_final_menghitung_tarif_dan_per_bulan(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    produk = await buat_produk(db_session, toko.toko.id)
    metode = await buat_metode_bayar(db_session, toko.toko.id)
    sekarang = datetime.now(UTC)
    lama = sekarang - timedelta(days=35)
    await _jual(client, toko, produk, metode, qty="2", nomor="OUT1-H1", tanggal=sekarang)  # 30.000
    await _jual(client, toko, produk, metode, qty="1", nomor="OUT1-H2", tanggal=lama)  # 15.000

    r = await client.get(
        "/laporan/pph-final", headers=toko.headers,
        params=_rentang(sekarang - timedelta(days=40), sekarang + timedelta(days=1)),
    )
    assert r.status_code == 200, r.text
    b = r.json()
    assert Decimal(b["tarif_persen"]) == Decimal("0.5")
    assert Decimal(b["omzet"]) == Decimal("45000")
    assert Decimal(b["pph_terutang"]) == Decimal("225.00")
    assert len(b["per_bulan"]) == 2
    assert b["per_bulan"][0]["bulan"] < b["per_bulan"][1]["bulan"]
    assert sum(Decimal(x["omzet"]) for x in b["per_bulan"]) == Decimal("45000")


async def test_laporan_pajak_digate_paket_izin_dan_rentang(client: AsyncClient, db_session: AsyncSession) -> None:
    sekarang = datetime.now(UTC)
    params = _rentang(sekarang - timedelta(days=1), sekarang + timedelta(days=1))
    for jalur, fitur in (("/laporan/rekap-pajak", "tax_recap"), ("/laporan/pph-final", "tax_pph")):
        gratis = await buat_toko_siap_pakai(db_session, nama_paket="Gratis")
        r = await client.get(jalur, headers=gratis.headers, params=params)
        assert r.status_code == 403 and r.json()["detail"]["fitur"] == fitur

        kasir = await buat_toko_siap_pakai(db_session, nama_role="Kasir", nama_paket="Bisnis")
        assert (await client.get(jalur, headers=kasir.headers, params=params)).status_code == 403

        bisnis = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
        terbalik = _rentang(sekarang, sekarang - timedelta(days=1))
        assert (await client.get(jalur, headers=bisnis.headers, params=terbalik)).status_code == 400
