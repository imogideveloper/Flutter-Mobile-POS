"""IMOGI no. 74: settlement & rekonsiliasi QRIS/e-wallet (catat dana masuk, bandingkan dengan penjualan non-tunai)."""

from datetime import UTC, datetime, timedelta
from decimal import Decimal

from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.produk import Produk
from tests.conftest import buat_metode_bayar, buat_toko_siap_pakai


async def _siapkan(db: AsyncSession):
    toko = await buat_toko_siap_pakai(db, nama_paket="Bisnis")
    produk = Produk(toko_id=toko.toko.id, nama="Kopi", harga_jual=Decimal("20000"), hpp=Decimal("8000"))
    db.add(produk)
    await db.commit()
    await db.refresh(produk)
    qris = await buat_metode_bayar(db, toko.toko.id, tipe="qris")
    tunai = await buat_metode_bayar(db, toko.toko.id, tipe="tunai")
    return toko, produk, qris, tunai


async def _jual(client, toko, produk, metode, *, qty: int, nomor: str) -> None:
    resp = await client.post(
        "/transaksi",
        headers=toko.headers,
        json={
            "outlet_id": str(toko.outlet.id),
            "nomor_struk": nomor,
            "tanggal": datetime.now(UTC).isoformat(),
            "items": [
                {
                    "produk_id": str(produk.id),
                    "nama_produk": produk.nama,
                    "qty": str(qty),
                    "harga_satuan": "20000",
                    "hpp_satuan": "8000",
                }
            ],
            "metode_bayar_id": str(metode.id),
            "total_bayar": str(qty * 20000),
        },
    )
    assert resp.status_code == 201, resp.text


def _rentang() -> dict:
    hari = datetime.now(UTC).date()
    return {"dari": str(hari - timedelta(days=1)), "sampai": str(hari + timedelta(days=1))}


async def test_rekonsiliasi_cocok_selisih_dan_belum_dicatat(client: AsyncClient, db_session: AsyncSession) -> None:
    toko, produk, qris, tunai = await _siapkan(db_session)
    await _jual(client, toko, produk, qris, qty=2, nomor="S-1")  # 40.000 QRIS
    await _jual(client, toko, produk, tunai, qty=1, nomor="S-2")  # tunai tidak ikut

    rek = (await client.get("/settlement/rekonsiliasi", headers=toko.headers, params=_rentang())).json()
    assert len(rek["baris"]) == 1, "hanya metode non-tunai"
    b = rek["baris"][0]
    assert Decimal(b["tercatat"]) == 40000 and b["status"] == "belum_dicatat"

    hari = str(datetime.now(UTC).date())
    r = await client.post(
        "/settlement",
        headers=toko.headers,
        json={"metode_bayar_id": str(qris.id), "tanggal": hari, "jumlah_diterima": "39700", "biaya": "300"},
    )
    assert r.status_code == 201, r.text
    rek = (await client.get("/settlement/rekonsiliasi", headers=toko.headers, params=_rentang())).json()
    assert rek["baris"][0]["status"] == "cocok" and Decimal(rek["total_selisih"]) == 0
    assert Decimal(rek["total_biaya"]) == 300

    await client.post(
        "/settlement",
        headers=toko.headers,
        json={"metode_bayar_id": str(qris.id), "tanggal": hari, "jumlah_diterima": "-0"},
    )
    sisa = (
        await client.post(
            "/settlement",
            headers=toko.headers,
            json={"metode_bayar_id": str(qris.id), "tanggal": hari, "jumlah_diterima": "100"},
        )
    ).json()
    rek = (await client.get("/settlement/rekonsiliasi", headers=toko.headers, params=_rentang())).json()
    assert rek["baris"][0]["status"] == "selisih" and Decimal(rek["baris"][0]["selisih"]) == -100

    assert (await client.delete(f"/settlement/{sisa['id']}", headers=toko.headers)).status_code == 204
    daftar = (await client.get("/settlement", headers=toko.headers, params=_rentang())).json()
    assert len(daftar) == 2 or len(daftar) == 3  # entri "-0" boleh tercatat sebagai nol


async def test_settlement_menolak_metode_tunai_dan_rentang_terlalu_panjang(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    toko, _, qris, tunai = await _siapkan(db_session)
    hari = str(datetime.now(UTC).date())
    r = await client.post(
        "/settlement", headers=toko.headers, json={"metode_bayar_id": str(tunai.id), "tanggal": hari, "jumlah_diterima": "1"}
    )
    assert r.status_code == 422
    r = await client.post(
        "/settlement", headers=toko.headers, json={"metode_bayar_id": str(qris.id), "tanggal": hari, "jumlah_diterima": "-5"}
    )
    assert r.status_code == 422
    r = await client.get("/settlement/rekonsiliasi", headers=toko.headers, params={"dari": "2026-01-01", "sampai": "2026-12-31"})
    assert r.status_code == 422


async def test_toko_lain_dan_paket_gratis(client: AsyncClient, db_session: AsyncSession) -> None:
    toko, _, qris, _ = await _siapkan(db_session)
    lain, _, _, _ = await _siapkan(db_session)
    hari = str(datetime.now(UTC).date())
    r = await client.post(
        "/settlement", headers=lain.headers, json={"metode_bayar_id": str(qris.id), "tanggal": hari, "jumlah_diterima": "1"}
    )
    assert r.status_code == 404, "metode milik toko lain"
    dibuat = (
        await client.post(
            "/settlement", headers=toko.headers, json={"metode_bayar_id": str(qris.id), "tanggal": hari, "jumlah_diterima": "1"}
        )
    ).json()
    assert (await client.delete(f"/settlement/{dibuat['id']}", headers=lain.headers)).status_code == 404

    gratis = await buat_toko_siap_pakai(db_session, nama_paket="Gratis")
    assert (await client.get("/settlement", headers=gratis.headers, params=_rentang())).status_code == 403


async def test_rekonsiliasi_mengelompokkan_tanggal_menurut_zona_waktu_hp(client: AsyncClient, db_session: AsyncSession) -> None:
    """Pembayaran 06.52 WIB (23.52 UTC hari sebelumnya) harus masuk tanggal lokal, bukan tanggal UTC (temuan HP 2026-11-26)."""
    from datetime import UTC, datetime

    from app.models.transaksi import Pembayaran, Transaksi

    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    metode = await buat_metode_bayar(db_session, toko.toko.id, tipe="qris")
    ts = datetime(2026, 11, 25, 23, 52, tzinfo=UTC)
    t = Transaksi(toko_id=toko.toko.id, outlet_id=toko.outlet.id, pengguna_id=toko.pengguna.id, nomor_struk="TZ-1", tanggal=ts, status="selesai",
                  subtotal=10000, total=10000, total_bayar=10000)
    db_session.add(t)
    await db_session.flush()
    db_session.add(Pembayaran(transaksi_id=t.id, metode_bayar_id=metode.id, jumlah=10000, status="berhasil", dibayar_pada=ts))
    await db_session.commit()

    p = {"dari": "2026-11-25", "sampai": "2026-11-26", "tz_menit": 420}
    baris = (await client.get("/settlement/rekonsiliasi", headers=toko.headers, params=p)).json()["baris"]
    assert [b["tanggal"] for b in baris] == ["2026-11-26"]
    p["tz_menit"] = 0
    baris = (await client.get("/settlement/rekonsiliasi", headers=toko.headers, params=p)).json()["baris"]
    assert [b["tanggal"] for b in baris] == ["2026-11-25"], "tanpa zona waktu tetap perilaku lama (UTC)"
