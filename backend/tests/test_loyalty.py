import uuid
from datetime import UTC, datetime
from decimal import Decimal

from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.pelanggan import AturanPoin, LevelMember, Pelanggan, RiwayatPoin
from app.models.transaksi import ItemTransaksi
from tests.conftest import buat_metode_bayar, buat_produk, buat_toko_siap_pakai


async def _buat_pelanggan(db: AsyncSession, toko_id, nama: str = "Budi") -> Pelanggan:
    pelanggan = Pelanggan(toko_id=toko_id, nama=nama)
    db.add(pelanggan)
    await db.commit()
    await db.refresh(pelanggan)
    return pelanggan


async def _aktifkan_aturan_poin(db: AsyncSession, toko_id, nominal_per_poin: Decimal = Decimal("10000")) -> None:
    db.add(AturanPoin(toko_id=toko_id, nominal_per_poin=nominal_per_poin, aktif=True))
    await db.commit()


async def _checkout(
    client: AsyncClient, toko_a, produk, metode, pelanggan, *,
    qty="2", nomor_struk="OUT1-LOY001", poin_ditukar: int = 0,
):
    resp = await client.post(
        "/transaksi",
        headers=toko_a.headers,
        json={
            "outlet_id": str(toko_a.outlet.id),
            "pelanggan_id": str(pelanggan.id) if pelanggan is not None else None,
            "nomor_struk": nomor_struk,
            "tanggal": datetime.now(UTC).isoformat(),
            "items": [
                {"produk_id": str(produk.id), "nama_produk": produk.nama, "qty": qty, "harga_satuan": "15000"}
            ],
            "metode_bayar_id": str(metode.id),
            "total_bayar": str(int(qty) * 15000),
            "poin_ditukar": poin_ditukar,
        },
    )
    return resp


async def _checkout_sukses(client: AsyncClient, toko_a, produk, metode, pelanggan, **kwargs) -> str:
    resp = await _checkout(client, toko_a, produk, metode, pelanggan, **kwargs)
    assert resp.status_code == 201, resp.text
    return resp.json()["id"]


async def test_checkout_memberi_poin_sesuai_aturan(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    # poin_loyalitas tingkat 1 (Pro+) - toko Gratis tidak dapat poin
    # (lihat test_checkout_tanpa_fitur_poin_loyalitas_tidak_memberi_poin).
    toko_a = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    produk = await buat_produk(db_session, toko_a.toko.id, harga_jual=Decimal("15000"))
    metode = await buat_metode_bayar(db_session, toko_a.toko.id)
    pelanggan = await _buat_pelanggan(db_session, toko_a.toko.id)
    await _aktifkan_aturan_poin(db_session, toko_a.toko.id, nominal_per_poin=Decimal("10000"))

    # total 30.000 / 10.000 per poin = 3 poin.
    await _checkout_sukses(client, toko_a, produk, metode, pelanggan)

    await db_session.refresh(pelanggan)
    assert pelanggan.poin == 3
    assert pelanggan.total_belanja == Decimal("30000")

    riwayat = (
        await db_session.execute(select(RiwayatPoin).where(RiwayatPoin.pelanggan_id == pelanggan.id))
    ).scalars().all()
    assert len(riwayat) == 1
    assert riwayat[0].poin == 3


async def _aktifkan_aturan_tukar(
    db: AsyncSession, toko_id, *,
    nilai_tukar_poin: Decimal = Decimal("100"), min_tukar_poin: int = 0,
) -> None:
    # nominal_per_poin=0 SENGAJA - mengisolasi test redemption dari efek
    # earning simultan (keduanya independen, lihat _ambil_aturan_untuk_
    # tukar vs _ambil_aturan_aktif di loyalty_service.py).
    db.add(
        AturanPoin(
            toko_id=toko_id, nominal_per_poin=Decimal("0"),
            nilai_tukar_poin=nilai_tukar_poin, min_tukar_poin=min_tukar_poin, aktif=True,
        )
    )
    await db.commit()


async def test_checkout_tukar_poin_mengurangi_total_dan_saldo_poin(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    toko_a = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    produk = await buat_produk(db_session, toko_a.toko.id, harga_jual=Decimal("15000"))
    metode = await buat_metode_bayar(db_session, toko_a.toko.id)
    pelanggan = await _buat_pelanggan(db_session, toko_a.toko.id)
    pelanggan.poin = 50
    await db_session.commit()
    await _aktifkan_aturan_tukar(db_session, toko_a.toko.id, nilai_tukar_poin=Decimal("100"))

    # 2 x 15.000 = 30.000 subtotal, tukar 20 poin x Rp100 = Rp2.000 diskon.
    resp = await _checkout(client, toko_a, produk, metode, pelanggan, poin_ditukar=20)
    assert resp.status_code == 201, resp.text
    body = resp.json()
    assert body["diskon_poin"] == "2000.00"
    assert body["total"] == "28000.00"

    await db_session.refresh(pelanggan)
    assert pelanggan.poin == 30

    riwayat_tukar = (
        await db_session.execute(
            select(RiwayatPoin).where(RiwayatPoin.pelanggan_id == pelanggan.id, RiwayatPoin.poin < 0)
        )
    ).scalars().all()
    assert len(riwayat_tukar) == 1
    assert riwayat_tukar[0].poin == -20


async def test_checkout_tukar_poin_saldo_tidak_cukup_ditolak(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    toko_a = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    produk = await buat_produk(db_session, toko_a.toko.id, harga_jual=Decimal("15000"))
    metode = await buat_metode_bayar(db_session, toko_a.toko.id)
    pelanggan = await _buat_pelanggan(db_session, toko_a.toko.id)
    pelanggan.poin = 5
    await db_session.commit()
    await _aktifkan_aturan_tukar(db_session, toko_a.toko.id, nilai_tukar_poin=Decimal("100"))

    resp = await _checkout(client, toko_a, produk, metode, pelanggan, poin_ditukar=20)
    assert resp.status_code == 400

    await db_session.refresh(pelanggan)
    assert pelanggan.poin == 5  # tidak berubah - checkout gagal, tidak jadi dipotong.


async def test_checkout_tukar_poin_kurang_dari_minimum_ditolak(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    toko_a = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    produk = await buat_produk(db_session, toko_a.toko.id, harga_jual=Decimal("15000"))
    metode = await buat_metode_bayar(db_session, toko_a.toko.id)
    pelanggan = await _buat_pelanggan(db_session, toko_a.toko.id)
    pelanggan.poin = 50
    await db_session.commit()
    await _aktifkan_aturan_tukar(db_session, toko_a.toko.id, nilai_tukar_poin=Decimal("100"), min_tukar_poin=30)

    resp = await _checkout(client, toko_a, produk, metode, pelanggan, poin_ditukar=10)
    assert resp.status_code == 400


async def test_checkout_tukar_poin_tanpa_pelanggan_ditolak(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    toko_a = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    produk = await buat_produk(db_session, toko_a.toko.id, harga_jual=Decimal("15000"))
    metode = await buat_metode_bayar(db_session, toko_a.toko.id)
    await _aktifkan_aturan_tukar(db_session, toko_a.toko.id, nilai_tukar_poin=Decimal("100"))

    resp = await _checkout(client, toko_a, produk, metode, None, poin_ditukar=10)
    assert resp.status_code == 400


async def test_checkout_tukar_poin_digate_fitur_poin_loyalitas(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    # toko_a (fixture) = paket Gratis, tidak punya fitur poin_loyalitas.
    produk = await buat_produk(db_session, toko_a.toko.id, harga_jual=Decimal("15000"))
    metode = await buat_metode_bayar(db_session, toko_a.toko.id)
    pelanggan = await _buat_pelanggan(db_session, toko_a.toko.id)
    pelanggan.poin = 50
    await db_session.commit()
    await _aktifkan_aturan_tukar(db_session, toko_a.toko.id, nilai_tukar_poin=Decimal("100"))

    resp = await _checkout(client, toko_a, produk, metode, pelanggan, poin_ditukar=10)
    assert resp.status_code == 403
    assert resp.json()["detail"]["kode"] == "fitur_terkunci"
    assert resp.json()["detail"]["fitur"] == "poin_loyalitas"


async def test_checkout_tukar_poin_dibatasi_tidak_melebihi_total(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    """qty=2 x Rp15.000 = Rp30.000, tukar 500 poin x Rp100 = Rp50.000
    (melebihi total) - diskon di-cap ke total, TIDAK membuat total negatif."""
    toko_a = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    produk = await buat_produk(db_session, toko_a.toko.id, harga_jual=Decimal("15000"))
    metode = await buat_metode_bayar(db_session, toko_a.toko.id)
    pelanggan = await _buat_pelanggan(db_session, toko_a.toko.id)
    pelanggan.poin = 500
    await db_session.commit()
    await _aktifkan_aturan_tukar(db_session, toko_a.toko.id, nilai_tukar_poin=Decimal("100"))

    resp = await _checkout(client, toko_a, produk, metode, pelanggan, poin_ditukar=500)
    assert resp.status_code == 201, resp.text
    body = resp.json()
    assert body["diskon_poin"] == "30000.00"
    assert body["total"] == "0.00"

    # Poin yang DIKURANGI tetap PENUH 500 (sesuai yang diminta kasir) -
    # bukan cuma 300 (senilai 30.000) - lihat docstring
    # hitung_dan_validasi_tukar_poin.
    await db_session.refresh(pelanggan)
    assert pelanggan.poin == 0


async def test_void_mengembalikan_poin_yang_ditukar(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    toko_a = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    produk = await buat_produk(db_session, toko_a.toko.id, harga_jual=Decimal("15000"))
    metode = await buat_metode_bayar(db_session, toko_a.toko.id)
    pelanggan = await _buat_pelanggan(db_session, toko_a.toko.id)
    pelanggan.poin = 50
    await db_session.commit()
    await _aktifkan_aturan_tukar(db_session, toko_a.toko.id, nilai_tukar_poin=Decimal("100"))

    transaksi_id = await _checkout_sukses(client, toko_a, produk, metode, pelanggan, poin_ditukar=20)
    await db_session.refresh(pelanggan)
    assert pelanggan.poin == 30

    resp = await client.post(
        f"/transaksi/{transaksi_id}/void", headers=toko_a.headers, json={"alasan": "Salah input"}
    )
    assert resp.status_code == 200

    await db_session.refresh(pelanggan)
    assert pelanggan.poin == 50  # 20 poin yang ditukar dikembalikan penuh.


async def test_checkout_poin_dikali_pengali_level_member(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    toko_a = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    produk = await buat_produk(db_session, toko_a.toko.id, harga_jual=Decimal("15000"))
    metode = await buat_metode_bayar(db_session, toko_a.toko.id)
    await _aktifkan_aturan_poin(db_session, toko_a.toko.id, nominal_per_poin=Decimal("10000"))

    level_emas = LevelMember(toko_id=toko_a.toko.id, nama="Emas", pengali_poin=2)
    db_session.add(level_emas)
    await db_session.flush()
    pelanggan = Pelanggan(toko_id=toko_a.toko.id, nama="Sari", level_member_id=level_emas.id)
    db_session.add(pelanggan)
    await db_session.commit()
    await db_session.refresh(pelanggan)

    # 30.000 / 10.000 = 3 poin dasar x pengali 2 = 6 poin.
    await _checkout_sukses(client, toko_a, produk, metode, pelanggan)

    await db_session.refresh(pelanggan)
    assert pelanggan.poin == 6


async def test_checkout_toko_gratis_tanpa_fitur_poin_loyalitas_tidak_memberi_poin(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    # tahap 3a A.1 - toko Gratis TIDAK dapat poin_loyalitas sama sekali,
    # walau aturan_poin-nya aktif - checkout tetap sukses (bukan error).
    produk = await buat_produk(db_session, toko_a.toko.id, harga_jual=Decimal("15000"))
    metode = await buat_metode_bayar(db_session, toko_a.toko.id)
    pelanggan = await _buat_pelanggan(db_session, toko_a.toko.id)
    await _aktifkan_aturan_poin(db_session, toko_a.toko.id, nominal_per_poin=Decimal("10000"))

    await _checkout_sukses(client, toko_a, produk, metode, pelanggan)

    await db_session.refresh(pelanggan)
    assert pelanggan.poin == 0


async def test_checkout_tanpa_aturan_poin_tidak_memberi_poin(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id, harga_jual=Decimal("15000"))
    metode = await buat_metode_bayar(db_session, toko_a.toko.id)
    pelanggan = await _buat_pelanggan(db_session, toko_a.toko.id)
    # TIDAK mengaktifkan aturan poin - harus no-op, bukan error.

    await _checkout_sukses(client, toko_a, produk, metode, pelanggan)

    await db_session.refresh(pelanggan)
    assert pelanggan.poin == 0
    assert pelanggan.total_belanja == Decimal("0")


async def test_void_membatalkan_seluruh_poin_dan_total_belanja(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    toko_a = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    produk = await buat_produk(db_session, toko_a.toko.id, harga_jual=Decimal("15000"))
    metode = await buat_metode_bayar(db_session, toko_a.toko.id)
    pelanggan = await _buat_pelanggan(db_session, toko_a.toko.id)
    await _aktifkan_aturan_poin(db_session, toko_a.toko.id, nominal_per_poin=Decimal("10000"))

    transaksi_id = await _checkout_sukses(client, toko_a, produk, metode, pelanggan)
    await db_session.refresh(pelanggan)
    assert pelanggan.poin == 3

    resp = await client.post(
        f"/transaksi/{transaksi_id}/void", headers=toko_a.headers, json={"alasan": "Salah input"}
    )
    assert resp.status_code == 200

    await db_session.refresh(pelanggan)
    assert pelanggan.poin == 0
    assert pelanggan.total_belanja == Decimal("0")


async def test_refund_sebagian_mengurangi_poin_proporsional(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    toko_a = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    produk = await buat_produk(db_session, toko_a.toko.id, harga_jual=Decimal("15000"))
    metode = await buat_metode_bayar(db_session, toko_a.toko.id)
    pelanggan = await _buat_pelanggan(db_session, toko_a.toko.id)
    await _aktifkan_aturan_poin(db_session, toko_a.toko.id, nominal_per_poin=Decimal("10000"))

    # 4 item x 15.000 = 60.000 -> 6 poin.
    transaksi_id = await _checkout_sukses(client, toko_a, produk, metode, pelanggan, qty="4")
    await db_session.refresh(pelanggan)
    assert pelanggan.poin == 6

    item_id = (
        await db_session.execute(
            select(ItemTransaksi).where(ItemTransaksi.transaksi_id == uuid.UUID(transaksi_id))
        )
    ).scalars().first().id

    # Refund 2 dari 4 item (separuh nilai transaksi) -> separuh poin dikurangi: 3.
    resp = await client.post(
        f"/transaksi/{transaksi_id}/refund",
        headers=toko_a.headers,
        json={"alasan": "2 rusak", "items": [{"item_transaksi_id": str(item_id), "qty": "2"}]},
    )
    assert resp.status_code == 201

    await db_session.refresh(pelanggan)
    assert pelanggan.poin == 3
    assert pelanggan.total_belanja == Decimal("30000")
