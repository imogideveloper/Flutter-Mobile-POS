"""IMOGI no. 84: laba rugi konsolidasi multi-outlet (per outlet + total toko; Owner/Manajer; digate paket)."""

import uuid
from datetime import UTC, date, datetime, timedelta
from decimal import Decimal

from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.outlet import Outlet
from app.models.pengeluaran import Pengeluaran
from app.models.produk import Produk
from tests.conftest import buat_metode_bayar, buat_toko_siap_pakai
from tests.test_akses_outlet import _buat_pengguna


def _rentang() -> dict:
    sekarang = datetime.now(UTC)
    return {"dari": (sekarang - timedelta(days=1)).isoformat(), "sampai": (sekarang + timedelta(days=1)).isoformat()}


async def _jual(client, toko, outlet_id, produk, metode, *, qty: str, nomor: str) -> None:
    resp = await client.post(
        "/transaksi",
        headers=toko.headers,
        json={
            "outlet_id": str(outlet_id),
            "nomor_struk": nomor,
            "tanggal": datetime.now(UTC).isoformat(),
            "items": [
                {
                    "produk_id": str(produk.id),
                    "nama_produk": produk.nama,
                    "qty": qty,
                    "harga_satuan": "20000",
                    "hpp_satuan": "8000",
                }
            ],
            "metode_bayar_id": str(metode.id),
            "total_bayar": str(Decimal(qty) * 20000),
        },
    )
    assert resp.status_code == 201, resp.text


async def _siapkan(db: AsyncSession):
    toko = await buat_toko_siap_pakai(db, nama_paket="Bisnis", jumlah_outlet=3)
    outlet_b = Outlet(toko_id=toko.toko.id, kode="OUT2", nama="Outlet B")
    db.add(outlet_b)
    produk = Produk(toko_id=toko.toko.id, nama="Kopi", harga_jual=Decimal("20000"), hpp=Decimal("8000"))
    db.add(produk)
    await db.commit()
    for obj in (outlet_b, produk):
        await db.refresh(obj)
    metode = await buat_metode_bayar(db, toko.toko.id)
    return toko, outlet_b, produk, metode


async def test_konsolidasi_per_outlet_dan_total_dengan_biaya_tanpa_outlet(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    toko, outlet_b, produk, metode = await _siapkan(db_session)
    outlet_a_id, outlet_b_id, toko_id = toko.outlet.id, outlet_b.id, toko.toko.id
    await _jual(client, toko, outlet_a_id, produk, metode, qty="2", nomor="KA-1")  # 40000, hpp 16000
    await _jual(client, toko, outlet_b_id, produk, metode, qty="3", nomor="KB-1")  # 60000, hpp 24000
    hari_ini = date.today()
    db_session.add_all(
        [
            Pengeluaran(toko_id=toko_id, outlet_id=outlet_a_id, tanggal=hari_ini, kategori="listrik_air", jumlah=Decimal("5000")),
            Pengeluaran(toko_id=toko_id, outlet_id=None, tanggal=hari_ini, kategori="sewa", jumlah=Decimal("7000")),
        ]
    )
    await db_session.commit()

    resp = await client.get("/laporan/laba-rugi-konsolidasi", headers=toko.headers, params=_rentang())
    assert resp.status_code == 200, resp.text
    data = resp.json()
    per = {o["outlet_nama"]: o["laporan"] for o in data["per_outlet"]}
    assert set(per) == {"Outlet Pusat", "Outlet B"}
    assert Decimal(per["Outlet Pusat"]["penjualan_bersih"]) == 40000
    assert Decimal(per["Outlet Pusat"]["laba_bersih"]) == 40000 - 16000 - 5000
    assert Decimal(per["Outlet B"]["penjualan_bersih"]) == 60000
    assert Decimal(per["Outlet B"]["laba_bersih"]) == 60000 - 24000

    total = data["total"]
    assert Decimal(total["penjualan_bersih"]) == 100000
    assert Decimal(total["hpp"]) == 40000
    assert Decimal(total["total_biaya_operasional"]) == 12000, "5000 outlet A + 7000 tanpa outlet"
    assert Decimal(total["laba_bersih"]) == 100000 - 40000 - 12000
    assert Decimal(data["biaya_tanpa_outlet"]) == 7000


async def test_konsolidasi_ditolak_untuk_paket_gratis_dan_kasir(client: AsyncClient, db_session: AsyncSession) -> None:
    gratis = await buat_toko_siap_pakai(db_session)
    resp = await client.get("/laporan/laba-rugi-konsolidasi", headers=gratis.headers, params=_rentang())
    assert resp.status_code == 403 and "fitur_terkunci" in resp.text

    toko, outlet_b, produk, metode = await _siapkan(db_session)
    kasir = await _buat_pengguna(
        db_session, toko_id=toko.toko.id, nama_role="Kasir", outlet_ids=[toko.outlet.id], nama="Kasir"
    )
    resp = await client.get("/laporan/laba-rugi-konsolidasi", headers=kasir.headers, params=_rentang())
    assert resp.status_code == 403


async def test_konsolidasi_tidak_memuat_outlet_toko_lain(client: AsyncClient, db_session: AsyncSession) -> None:
    toko, outlet_b, produk, metode = await _siapkan(db_session)
    lain = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    resp = await client.get("/laporan/laba-rugi-konsolidasi", headers=lain.headers, params=_rentang())
    assert resp.status_code == 200
    assert [o["outlet_id"] for o in resp.json()["per_outlet"]] == [str(lain.outlet.id)]
