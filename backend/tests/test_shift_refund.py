"""Kas seharusnya shift setelah refund (AT2, docs/perlu_konfirmasi.md).

Bug nyata dari uji di HP: refund "Sama seperti transaksi asal" (metode_bayar_id kosong) tidak pernah dikurangkan
dari kas seharusnya, sehingga tutup shift menunjukkan selisih kurang palsu."""

import uuid
from datetime import UTC, datetime
from decimal import Decimal

from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.transaksi import ItemTransaksi
from tests.conftest import buat_metode_bayar, buat_produk


async def _buka_shift(client: AsyncClient, toko, modal: str = "100000") -> str:
    resp = await client.post(
        "/shift/buka", headers=toko.headers, json={"outlet_id": str(toko.outlet.id), "modal_awal": modal}
    )
    assert resp.status_code == 201, resp.text
    return resp.json()["id"]


async def _jual(client: AsyncClient, toko, shift_id: str, produk, nomor: str, qty: str, metode, **tambahan) -> str:
    total = Decimal(qty) * Decimal(str(produk.harga_jual))
    resp = await client.post(
        "/transaksi",
        headers=toko.headers,
        json={
            "outlet_id": str(toko.outlet.id),
            "shift_id": shift_id,
            "nomor_struk": nomor,
            "tanggal": datetime.now(UTC).isoformat(),
            "items": [
                {
                    "produk_id": str(produk.id),
                    "nama_produk": produk.nama,
                    "qty": qty,
                    "harga_satuan": str(produk.harga_jual),
                }
            ],
            "metode_bayar_id": str(metode.id),
            "total_bayar": str(total),
            **tambahan,
        },
    )
    assert resp.status_code == 201, resp.text
    return resp.json()["id"]


async def _item_id(db: AsyncSession, transaksi_id: str) -> str:
    item = (
        await db.execute(select(ItemTransaksi).where(ItemTransaksi.transaksi_id == uuid.UUID(transaksi_id)))
    ).scalars().first()
    return str(item.id)


async def _refund(client: AsyncClient, toko, db: AsyncSession, transaksi_id: str, qty: str, **tambahan) -> dict:
    resp = await client.post(
        f"/transaksi/{transaksi_id}/refund",
        headers=toko.headers,
        json={
            "alasan": "uji",
            "items": [{"item_transaksi_id": await _item_id(db, transaksi_id), "qty": qty}],
            **tambahan,
        },
    )
    assert resp.status_code == 201, resp.text
    return resp.json()


async def _kas_seharusnya(client: AsyncClient, toko, shift_id: str, kas_aktual: str) -> Decimal:
    resp = await client.post(f"/shift/{shift_id}/tutup", headers=toko.headers, json={"kas_aktual": kas_aktual})
    assert resp.status_code == 200, resp.text
    return Decimal(resp.json()["kas_seharusnya"])


async def test_refund_tunai_tanpa_metode_eksplisit_mengurangi_kas(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    """Kasus dari HP: jual tunai lalu refund dengan 'Sama seperti transaksi asal' (tanpa metode_bayar_id)."""
    produk = await buat_produk(db_session, toko_a.toko.id, harga_jual=Decimal("15000"))
    tunai = await buat_metode_bayar(db_session, toko_a.toko.id, tipe="tunai")
    shift_id = await _buka_shift(client, toko_a)
    transaksi_id = await _jual(client, toko_a, shift_id, produk, "OUT1-K1", "4", tunai)  # tunai masuk 60.000
    refund = await _refund(client, toko_a, db_session, transaksi_id, "1")  # refund 15.000, metode tidak diisi
    assert Decimal(refund["kas_dikembalikan"]) == Decimal("15000")

    # 100.000 modal + 60.000 tunai - 15.000 refund = 145.000
    assert await _kas_seharusnya(client, toko_a, shift_id, "145000") == Decimal("145000")


async def test_refund_transaksi_qris_tanpa_metode_tidak_mengurangi_kas(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    """Uang QRIS tidak pernah masuk laci, jadi refund-nya juga tidak boleh mengurangi laci."""
    produk = await buat_produk(db_session, toko_a.toko.id, harga_jual=Decimal("15000"))
    qris = await buat_metode_bayar(db_session, toko_a.toko.id, tipe="qris", masuk_laci=False)
    shift_id = await _buka_shift(client, toko_a)
    transaksi_id = await _jual(client, toko_a, shift_id, produk, "OUT1-K2", "2", qris)
    await _refund(client, toko_a, db_session, transaksi_id, "1")

    assert await _kas_seharusnya(client, toko_a, shift_id, "100000") == Decimal("100000")


async def test_refund_bayar_campur_tanpa_metode_dibagi_menurut_porsi_tunai(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    """Keputusan sementara: refund tanpa metode eksplisit dibagi proporsional ke porsi pembayaran tunai."""
    produk = await buat_produk(db_session, toko_a.toko.id, harga_jual=Decimal("50000"))
    tunai = await buat_metode_bayar(db_session, toko_a.toko.id, tipe="tunai")
    kartu = await buat_metode_bayar(db_session, toko_a.toko.id, tipe="kartu", masuk_laci=False)
    shift_id = await _buka_shift(client, toko_a, modal="0")
    transaksi_id = await _jual(
        client,
        toko_a,
        shift_id,
        produk,
        "OUT1-K3",
        "2",  # total 100.000: tunai 40.000 + kartu 60.000
        tunai,
        split_pembayaran=[
            {"metode_bayar_id": str(tunai.id), "jumlah": "40000"},
            {"metode_bayar_id": str(kartu.id), "jumlah": "60000"},
        ],
    )
    await _refund(client, toko_a, db_session, transaksi_id, "1")  # refund 50.000, porsi tunai 40%

    # tunai masuk 40.000 - refund tunai (50.000 x 40% = 20.000) = 20.000
    assert await _kas_seharusnya(client, toko_a, shift_id, "20000") == Decimal("20000")


async def test_refund_dengan_metode_eksplisit_mengikuti_metode_itu(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id, harga_jual=Decimal("15000"))
    tunai = await buat_metode_bayar(db_session, toko_a.toko.id, tipe="tunai")
    transfer = await buat_metode_bayar(db_session, toko_a.toko.id, tipe="transfer", masuk_laci=False)

    shift_a = await _buka_shift(client, toko_a, modal="0")
    transaksi_a = await _jual(client, toko_a, shift_a, produk, "OUT1-K4", "2", tunai)
    await _refund(client, toko_a, db_session, transaksi_a, "1", metode_bayar_id=str(tunai.id))
    assert await _kas_seharusnya(client, toko_a, shift_a, "15000") == Decimal("15000"), "refund lewat tunai"

    shift_b = await _buka_shift(client, toko_a, modal="0")
    transaksi_b = await _jual(client, toko_a, shift_b, produk, "OUT1-K5", "2", tunai)
    await _refund(client, toko_a, db_session, transaksi_b, "1", metode_bayar_id=str(transfer.id))
    assert await _kas_seharusnya(client, toko_a, shift_b, "30000") == Decimal("30000"), (
        "uang dikembalikan lewat transfer, laci tidak berkurang"
    )


async def test_refund_dengan_shift_id_mengurangi_shift_tempat_refund_diproses(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    """Bila klien mengirim shift_id, refund dihitung di shift tempat uang keluar dari laci, bukan shift asal."""
    produk = await buat_produk(db_session, toko_a.toko.id, harga_jual=Decimal("15000"))
    tunai = await buat_metode_bayar(db_session, toko_a.toko.id, tipe="tunai")
    shift_lama = await _buka_shift(client, toko_a, modal="0")
    transaksi_id = await _jual(client, toko_a, shift_lama, produk, "OUT1-K6", "2", tunai)
    # Shift lama masih terbuka (dua shift terbuka di outlet berbeda tidak dibolehkan, jadi tidak ditutup di sini):
    # yang diuji adalah ke shift mana refund dibukukan.
    resp_lain = await client.get(f"/laporan/shift/{shift_lama}", headers=toko_a.headers)
    assert resp_lain.status_code == 200
    assert Decimal(resp_lain.json()["kas_seharusnya"]) == Decimal("30000")

    await _refund(client, toko_a, db_session, transaksi_id, "1", shift_id=shift_lama)
    resp = await client.get(f"/laporan/shift/{shift_lama}", headers=toko_a.headers)
    assert Decimal(resp.json()["kas_seharusnya"]) == Decimal("15000"), "refund dibukukan ke shift yang dikirim"


async def test_refund_tanpa_shift_id_dibukukan_ke_shift_transaksi_asal(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    """Perilaku bawaan yang didokumentasikan (AT3): tanpa shift_id, refund memakai shift transaksi asal.
    Aplikasi saat ini tidak mengirim shift_id, jadi refund yang diproses di shift berikutnya mengurangi shift lama."""
    produk = await buat_produk(db_session, toko_a.toko.id, harga_jual=Decimal("15000"))
    tunai = await buat_metode_bayar(db_session, toko_a.toko.id, tipe="tunai")
    shift_lama = await _buka_shift(client, toko_a, modal="0")
    transaksi_id = await _jual(client, toko_a, shift_lama, produk, "OUT1-K7", "2", tunai)
    assert await _kas_seharusnya(client, toko_a, shift_lama, "30000") == Decimal("30000")

    shift_baru = await _buka_shift(client, toko_a, modal="50000")
    await _refund(client, toko_a, db_session, transaksi_id, "1")
    resp = await client.get(f"/laporan/shift/{shift_baru}", headers=toko_a.headers)
    assert Decimal(resp.json()["kas_seharusnya"]) == Decimal("50000"), "shift baru tidak berkurang (AT3)"
