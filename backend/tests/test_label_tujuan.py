"""IMOGI no. 18: label tujuan pembayaran (GoPay, OVO, ShopeePay, bank) untuk rekonsiliasi."""

from datetime import UTC, datetime
from decimal import Decimal

import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from app.services.label_pembayaran import MAKS_LABEL, normalisasi_label_tujuan
from tests.conftest import buat_metode_bayar, buat_produk, buat_toko_siap_pakai


def test_normalisasi_merapikan_dan_membuang_duplikat() -> None:
    assert normalisasi_label_tujuan(" GoPay , ovo,,  gopay , Shopee   Pay ") == "GoPay,ovo,Shopee Pay"
    assert normalisasi_label_tujuan("") is None
    assert normalisasi_label_tujuan("  , ,") is None
    assert normalisasi_label_tujuan(None) is None


def test_normalisasi_menolak_terlalu_banyak_atau_terlalu_panjang() -> None:
    with pytest.raises(ValueError):
        normalisasi_label_tujuan(",".join(f"L{i}" for i in range(MAKS_LABEL + 1)))
    with pytest.raises(ValueError):
        normalisasi_label_tujuan("x" * 31)
    assert normalisasi_label_tujuan(",".join(f"L{i}" for i in range(MAKS_LABEL))) is not None


async def test_label_tujuan_diatur_di_paket_enterprise_dan_ditolak_di_gratis(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    gratis = await buat_toko_siap_pakai(db_session, nama_paket="Gratis")
    qris_gratis = await buat_metode_bayar(db_session, gratis.toko.id, tipe="qris")
    ditolak = await client.patch(
        f"/metode-bayar/{qris_gratis.id}", headers=gratis.headers, json={"label_tujuan": "GoPay,OVO"}
    )
    assert ditolak.status_code == 403
    assert ditolak.json()["detail"]["fitur"] == "label_pembayaran"

    bisnis = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    qris = await buat_metode_bayar(db_session, bisnis.toko.id, tipe="qris")
    resp = await client.patch(
        f"/metode-bayar/{qris.id}", headers=bisnis.headers, json={"label_tujuan": " GoPay , OVO, gopay "}
    )
    assert resp.status_code == 200, resp.text
    assert resp.json()["label_tujuan"] == "GoPay,OVO"

    daftar = {m["id"]: m for m in (await client.get("/metode-bayar", headers=bisnis.headers)).json()}
    assert daftar[str(qris.id)]["label_tujuan"] == "GoPay,OVO"

    # Mengosongkan menghapus label.
    kosong = await client.patch(f"/metode-bayar/{qris.id}", headers=bisnis.headers, json={"label_tujuan": ""})
    assert kosong.status_code == 200 and kosong.json()["label_tujuan"] is None


async def test_label_tujuan_tidak_untuk_tunai_dan_divalidasi(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    tunai = await buat_metode_bayar(db_session, toko.toko.id, tipe="tunai")
    kartu = await buat_metode_bayar(db_session, toko.toko.id, tipe="kartu")

    r1 = await client.patch(f"/metode-bayar/{tunai.id}", headers=toko.headers, json={"label_tujuan": "GoPay"})
    assert r1.status_code == 422
    r2 = await client.patch(f"/metode-bayar/{kartu.id}", headers=toko.headers, json={"label_tujuan": "x" * 40})
    assert r2.status_code == 422
    r3 = await client.patch(
        f"/metode-bayar/{kartu.id}", headers=toko.headers, json={"label_tujuan": "BCA,Mandiri"}
    )
    assert r3.status_code == 200


async def test_laporan_memisahkan_baris_per_label_tujuan(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Gratis")
    produk = await buat_produk(db_session, toko.toko.id, harga_jual=Decimal("10000"))
    qris = await buat_metode_bayar(db_session, toko.toko.id, tipe="qris")

    async def bayar(nomor: str, payload: dict | None) -> None:
        body = {
            "outlet_id": str(toko.outlet.id),
            "nomor_struk": nomor,
            "tanggal": datetime.now(UTC).isoformat(),
            "items": [{"produk_id": str(produk.id), "nama_produk": produk.nama, "qty": "1", "harga_satuan": "10000"}],
            "metode_bayar_id": str(qris.id),
            "total_bayar": "10000",
        }
        if payload is not None:
            body["payload_gateway"] = payload
        resp = await client.post("/transaksi", headers=toko.headers, json=body)
        assert resp.status_code == 201, resp.text

    await bayar("LT-1", {"label_tujuan": "GoPay"})
    await bayar("LT-2", {"label_tujuan": "GoPay"})
    await bayar("LT-3", {"label_tujuan": "OVO"})
    await bayar("LT-4", None)
    await bayar("LT-5", {"metode": "qris_statis_manual", "label_tujuan": "BCA"})

    sekarang = datetime.now(UTC)
    resp = await client.get(
        "/laporan/penjualan",
        headers=toko.headers,
        params={"dari": sekarang.replace(hour=0, minute=0, second=0).isoformat(), "sampai": sekarang.isoformat()},
    )
    assert resp.status_code == 200
    total = {m["nama"]: Decimal(m["total"]) for m in resp.json()["metode_bayar"]}
    assert total["Qris · GoPay"] == Decimal("20000")
    assert total["Qris · OVO"] == Decimal("10000")
    assert total["Qris"] == Decimal("10000")
    assert total["QRIS manual (belum terverifikasi) · BCA"] == Decimal("10000")


def test_label_kartu_menyertakan_jenis_dan_mesin_edc():
    from app.services.laporan_service import _label_pembayaran

    assert _label_pembayaran("Kartu", {"jenis_kartu": "debit", "label_tujuan": "EDC BCA"}) == "Kartu · Debit · EDC BCA"
    assert _label_pembayaran("Kartu", {"jenis_kartu": "kredit"}) == "Kartu · Kredit"
    assert _label_pembayaran("Kartu", {"label_tujuan": "EDC BCA"}) == "Kartu · EDC BCA"
    assert _label_pembayaran("Kartu", {"jenis_kartu": "aneh"}) == "Kartu"
    assert _label_pembayaran("Kartu", None) == "Kartu"
