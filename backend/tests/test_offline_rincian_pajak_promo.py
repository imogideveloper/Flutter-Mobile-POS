"""Temuan#1 (rapikan laporan F3-A/F) - transaksi offline (push, body.id
terisi) sekarang bisa kirim rincian pajak/service & promo/member yang
sudah dihitung HP, disimpan ke transaksi_pajak/transaksi_promo APA ADANYA
(lihat checkout_service.py). Ini membuat refund proporsional & laporan
pajak per-jenis konsisten antara transaksi online dan offline."""

import uuid
from datetime import UTC, datetime
from decimal import Decimal

from httpx import AsyncClient
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.audit import AuditLog
from app.models.promo import Pajak, Promo
from app.models.transaksi import ItemTransaksi, Transaksi, TransaksiPajak, TransaksiPromo
from tests.conftest import buat_metode_bayar, buat_produk


async def _buat_pajak(db: AsyncSession, toko_id, *, nama: str, tipe: str, persen: Decimal) -> Pajak:
    pajak = Pajak(toko_id=toko_id, nama=nama, tipe=tipe, persen=persen, termasuk_harga=False)
    db.add(pajak)
    await db.commit()
    await db.refresh(pajak)
    return pajak


async def _buat_promo(db: AsyncSession, toko_id, *, nama: str, nilai: Decimal) -> Promo:
    promo = Promo(toko_id=toko_id, nama=nama, tipe="nominal", nilai=nilai, cakupan="transaksi")
    db.add(promo)
    await db.commit()
    await db.refresh(promo)
    return promo


def _body_checkout_offline(*, transaksi_id, outlet_id, metode_id, produk, qty, harga_satuan, extra: dict) -> dict:
    subtotal = Decimal(qty) * Decimal(harga_satuan)
    body = {
        "id": str(transaksi_id),
        "outlet_id": str(outlet_id),
        "nomor_struk": f"OFF-{str(transaksi_id)[:8]}",
        "tanggal": datetime.now(UTC).isoformat(),
        "items": [
            {
                "produk_id": str(produk.id),
                "nama_produk": produk.nama,
                "qty": str(qty),
                "harga_satuan": str(harga_satuan),
            }
        ],
        "metode_bayar_id": str(metode_id),
        "total_bayar": str(subtotal),
        "subtotal_klien": str(subtotal),
    }
    body.update(extra)
    return body


async def test_checkout_offline_rincian_pajak_promo_tersimpan_benar(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id, harga_jual=Decimal("50000"))
    metode = await buat_metode_bayar(db_session, toko_a.toko.id)
    ppn = await _buat_pajak(db_session, toko_a.toko.id, nama="PPN", tipe="pajak", persen=Decimal("11"))
    service = await _buat_pajak(db_session, toko_a.toko.id, nama="Service", tipe="service", persen=Decimal("5"))
    promo = await _buat_promo(db_session, toko_a.toko.id, nama="Promo Lebaran", nilai=Decimal("10000"))

    transaksi_id = uuid.uuid4()
    total_bayar = Decimal("95500")  # 100000 - 10000 diskon member - 10000 promo + 5000 service + 11000-ish PPN (angka bebas, server tidak hitung ulang menimpa)
    body = _body_checkout_offline(
        transaksi_id=transaksi_id,
        outlet_id=toko_a.outlet.id,
        metode_id=metode.id,
        produk=produk,
        qty="2",
        harga_satuan="50000",
        extra={
            "total_bayar": str(total_bayar),
            "total_diskon_klien": "20000",
            "total_pajak_klien": "15500",
            "total_klien": str(total_bayar),
            "rincian_pajak_klien": [
                {"pajak_id": str(ppn.id), "nama": "PPN", "persen": "11", "jumlah": "9900"},
                {"pajak_id": str(service.id), "nama": "Service", "persen": "5", "jumlah": "5600"},
            ],
            "rincian_promo_klien": [
                {"promo_id": None, "nama": "Diskon member", "jumlah_diskon": "10000"},
                {"promo_id": str(promo.id), "nama": "Promo Lebaran", "jumlah_diskon": "10000"},
            ],
        },
    )
    resp = await client.post("/transaksi", headers=toko_a.headers, json=body)
    assert resp.status_code == 201, resp.text

    pajak_rows = (
        await db_session.execute(select(TransaksiPajak).where(TransaksiPajak.transaksi_id == transaksi_id))
    ).scalars().all()
    assert len(pajak_rows) == 2
    by_nama = {p.nama: p for p in pajak_rows}
    assert by_nama["PPN"].pajak_id == ppn.id
    assert Decimal(str(by_nama["PPN"].jumlah)) == Decimal("9900.00")
    assert by_nama["Service"].pajak_id == service.id
    assert Decimal(str(by_nama["Service"].jumlah)) == Decimal("5600.00")

    promo_rows = (
        await db_session.execute(select(TransaksiPromo).where(TransaksiPromo.transaksi_id == transaksi_id))
    ).scalars().all()
    assert len(promo_rows) == 2
    member_row = next(p for p in promo_rows if p.promo_id is None)
    assert member_row.nama == "Diskon member"
    assert Decimal(str(member_row.jumlah_diskon)) == Decimal("10000.00")
    promo_row = next(p for p in promo_rows if p.promo_id is not None)
    assert promo_row.promo_id == promo.id
    assert Decimal(str(promo_row.jumlah_diskon)) == Decimal("10000.00")


async def test_checkout_offline_pajak_id_tak_dikenal_disimpan_null_dan_audit(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id, harga_jual=Decimal("20000"))
    metode = await buat_metode_bayar(db_session, toko_a.toko.id)
    pajak_asing = uuid.uuid4()  # tidak ada di tabel pajak sama sekali

    transaksi_id = uuid.uuid4()
    body = _body_checkout_offline(
        transaksi_id=transaksi_id,
        outlet_id=toko_a.outlet.id,
        metode_id=metode.id,
        produk=produk,
        qty="1",
        harga_satuan="20000",
        extra={
            "rincian_pajak_klien": [
                {"pajak_id": str(pajak_asing), "nama": "Pajak Misterius", "persen": "7", "jumlah": "1400"},
            ],
        },
    )
    resp = await client.post("/transaksi", headers=toko_a.headers, json=body)
    assert resp.status_code == 201, resp.text

    row = (
        await db_session.execute(select(TransaksiPajak).where(TransaksiPajak.transaksi_id == transaksi_id))
    ).scalar_one()
    assert row.pajak_id is None
    assert row.nama == "Pajak Misterius"

    audit = (
        await db_session.execute(
            select(AuditLog).where(
                AuditLog.aksi == "offline_pajak_id_tak_dikenal", AuditLog.record_id == transaksi_id
            )
        )
    ).scalar_one()
    assert audit.data_lama["pajak_id"] == str(pajak_asing)


async def test_checkout_offline_promo_id_tak_dikenal_disimpan_null_dan_audit(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id, harga_jual=Decimal("20000"))
    metode = await buat_metode_bayar(db_session, toko_a.toko.id)
    promo_asing = uuid.uuid4()

    transaksi_id = uuid.uuid4()
    body = _body_checkout_offline(
        transaksi_id=transaksi_id,
        outlet_id=toko_a.outlet.id,
        metode_id=metode.id,
        produk=produk,
        qty="1",
        harga_satuan="20000",
        extra={
            "rincian_promo_klien": [
                {"promo_id": str(promo_asing), "nama": "Promo Misterius", "jumlah_diskon": "2000"},
            ],
        },
    )
    resp = await client.post("/transaksi", headers=toko_a.headers, json=body)
    assert resp.status_code == 201, resp.text

    row = (
        await db_session.execute(select(TransaksiPromo).where(TransaksiPromo.transaksi_id == transaksi_id))
    ).scalar_one()
    assert row.promo_id is None
    assert row.nama == "Promo Misterius"

    audit = (
        await db_session.execute(
            select(AuditLog).where(
                AuditLog.aksi == "offline_promo_id_tak_dikenal", AuditLog.record_id == transaksi_id
            )
        )
    ).scalar_one()
    assert audit.data_lama["promo_id"] == str(promo_asing)


async def test_refund_transaksi_offline_dgn_rincian_proporsional_penuh_sama_dgn_total(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    """Refund PENUH (semua item) atas transaksi OFFLINE yang sudah punya
    rincian pajak/promo harus PERSIS sama dgn total transaksi - exact sama
    persyaratan dgn test online yg sudah ada (test_refund.py), membuktikan
    refund offline SEKARANG ikut jalur proporsional, bukan formula sederhana."""

    produk = await buat_produk(db_session, toko_a.toko.id, harga_jual=Decimal("50000"))
    metode = await buat_metode_bayar(db_session, toko_a.toko.id)
    ppn = await _buat_pajak(db_session, toko_a.toko.id, nama="PPN", tipe="pajak", persen=Decimal("11"))

    transaksi_id = uuid.uuid4()
    # subtotal 100000, promo 10000 -> basis 90000, PPN 11% = 9900 -> total 99900
    body = _body_checkout_offline(
        transaksi_id=transaksi_id,
        outlet_id=toko_a.outlet.id,
        metode_id=metode.id,
        produk=produk,
        qty="2",
        harga_satuan="50000",
        extra={
            "total_bayar": "99900",
            "total_diskon_klien": "10000",
            "total_pajak_klien": "9900",
            "total_klien": "99900",
            "rincian_pajak_klien": [{"pajak_id": str(ppn.id), "nama": "PPN", "persen": "11", "jumlah": "9900"}],
            "rincian_promo_klien": [{"promo_id": None, "nama": "Diskon member", "jumlah_diskon": "10000"}],
        },
    )
    resp = await client.post("/transaksi", headers=toko_a.headers, json=body)
    assert resp.status_code == 201, resp.text

    transaksi = await db_session.get(Transaksi, transaksi_id)
    assert Decimal(str(transaksi.total)) == Decimal("99900.00")

    item = (
        await db_session.execute(select(ItemTransaksi).where(ItemTransaksi.transaksi_id == transaksi_id))
    ).scalar_one()

    resp_refund = await client.post(
        f"/transaksi/{transaksi_id}/refund",
        headers=toko_a.headers,
        json={"alasan": "retur semua", "items": [{"item_transaksi_id": str(item.id), "qty": "2"}]},
    )
    assert resp_refund.status_code == 201, resp_refund.text
    assert Decimal(str(resp_refund.json()["total"])) == Decimal(str(transaksi.total))


async def test_laporan_pajak_per_jenis_campuran_online_dan_offline(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    """Bukan endpoint baru - verifikasi langsung lewat query agregat
    transaksi_pajak GROUP BY nama (BUKAN pajak_id - checkout ONLINE pun
    tidak mengisi TransaksiPajak.pajak_id, cuma nama/persen/jumlah; itu
    keterbatasan lama yang terpisah dari temuan#1, lihat
    checkout_service.py bagian `if not is_push_offline`) bahwa transaksi
    ONLINE (server menghitung sendiri) dan OFFLINE (HP kirim rincian) ikut
    terjumlah konsisten per jenis pajak."""

    produk = await buat_produk(db_session, toko_a.toko.id, harga_jual=Decimal("100000"))
    metode = await buat_metode_bayar(db_session, toko_a.toko.id)
    ppn = await _buat_pajak(db_session, toko_a.toko.id, nama="PPN", tipe="pajak", persen=Decimal("10"))

    # Transaksi ONLINE - server hitung sendiri PPN 10% dari 100000 = 10000.
    resp_online = await client.post(
        "/transaksi",
        headers=toko_a.headers,
        json={
            "outlet_id": str(toko_a.outlet.id),
            "nomor_struk": "ON-PJK-1",
            "tanggal": datetime.now(UTC).isoformat(),
            "items": [
                {"produk_id": str(produk.id), "nama_produk": produk.nama, "qty": "1", "harga_satuan": "100000"}
            ],
            "metode_bayar_id": str(metode.id),
            "total_bayar": "110000",
        },
    )
    assert resp_online.status_code == 201, resp_online.text

    # Transaksi OFFLINE - HP kirim rincian PPN yang sama persis (pajak_id valid).
    transaksi_offline_id = uuid.uuid4()
    body_offline = _body_checkout_offline(
        transaksi_id=transaksi_offline_id,
        outlet_id=toko_a.outlet.id,
        metode_id=metode.id,
        produk=produk,
        qty="1",
        harga_satuan="100000",
        extra={
            "total_bayar": "110000",
            "total_pajak_klien": "10000",
            "total_klien": "110000",
            "rincian_pajak_klien": [{"pajak_id": str(ppn.id), "nama": "PPN", "persen": "10", "jumlah": "10000"}],
        },
    )
    resp_offline = await client.post("/transaksi", headers=toko_a.headers, json=body_offline)
    assert resp_offline.status_code == 201, resp_offline.text

    total_ppn = await db_session.scalar(
        select(func.coalesce(func.sum(TransaksiPajak.jumlah), 0))
        .join(Transaksi, Transaksi.id == TransaksiPajak.transaksi_id)
        .where(Transaksi.toko_id == toko_a.toko.id, TransaksiPajak.nama == "PPN")
    )
    assert Decimal(str(total_ppn)) == Decimal("20000.00")
