"""Integritas sync (FASE 3, TASK-115, BUG-018): retry tidak menggandakan data, kegagalan satu
item tidak menahan item lain, dan penolakan tercatat untuk ditelusuri."""

import uuid
from datetime import UTC, datetime

from httpx import AsyncClient
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.audit import SyncLog
from app.models.stok import Stok
from app.models.transaksi import Shift, Transaksi
from tests.conftest import buat_metode_bayar, buat_perangkat, buat_produk


def _trx(toko, produk, metode, *, trx_id=None, shift_id=None, nomor="OUT1-INT-0001", qty="2") -> dict:
    return {
        "id": str(trx_id or uuid.uuid4()),
        "outlet_id": str(toko.outlet.id),
        **({"shift_id": str(shift_id)} if shift_id else {}),
        "nomor_struk": nomor,
        "tanggal": datetime.now(UTC).isoformat(),
        "items": [{"produk_id": str(produk.id), "nama_produk": produk.nama, "qty": qty, "harga_satuan": "15000"}],
        "metode_bayar_id": str(metode.id),
        "total_bayar": "30000",
    }


def _shift(toko, shift_id, *, status="tutup") -> dict:
    sekarang = datetime.now(UTC).isoformat()
    item = {
        "id": str(shift_id),
        "outlet_id": str(toko.outlet.id),
        "dibuka_pada": sekarang,
        "modal_awal": "100000",
        "status": status,
    }
    if status == "tutup":
        item |= {"ditutup_pada": sekarang, "kas_aktual": "130000"}
    return item


async def _hitung(db: AsyncSession, model, *kondisi) -> int:
    return (await db.execute(select(func.count()).select_from(model).where(*kondisi))).scalar_one()


async def test_retry_batch_yang_sama_tidak_menggandakan_transaksi_shift_maupun_stok(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id)
    metode = await buat_metode_bayar(db_session, toko_a.toko.id)
    perangkat = await buat_perangkat(db_session, toko_a.toko.id, toko_a.outlet.id)
    db_session.add(Stok(outlet_id=toko_a.outlet.id, produk_id=produk.id, jumlah=10))
    await db_session.commit()

    shift_id, trx_id = uuid.uuid4(), uuid.uuid4()
    payload = {
        "perangkat_id": str(perangkat.id),
        "shift": [_shift(toko_a, shift_id)],
        "transaksi": [_trx(toko_a, produk, metode, trx_id=trx_id, shift_id=shift_id)],
    }

    for _ in range(3):  # HP mengulang karena koneksi putus
        resp = await client.post("/sync/push", headers=toko_a.headers, json=payload)
        assert resp.status_code == 200
        assert resp.json()["transaksi"][0]["status"] == "diterima"

    assert await _hitung(db_session, Transaksi, Transaksi.id == trx_id) == 1
    assert await _hitung(db_session, Shift, Shift.id == shift_id) == 1
    stok = (await db_session.execute(select(Stok).where(Stok.produk_id == produk.id))).scalar_one()
    await db_session.refresh(stok)
    assert float(stok.jumlah) == 8, "stok hanya terpotong sekali (10 - 2), bukan tiap retry"


async def test_shift_yang_sudah_tutup_tidak_dibuka_lagi_oleh_push_terlambat(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    perangkat = await buat_perangkat(db_session, toko_a.toko.id, toko_a.outlet.id)
    shift_id = uuid.uuid4()
    url = "/sync/push"

    await client.post(url, headers=toko_a.headers, json={"perangkat_id": str(perangkat.id), "shift": [_shift(toko_a, shift_id)]})
    # Payload lama "buka" tiba terlambat (retry dari antrean HP).
    resp = await client.post(
        url, headers=toko_a.headers, json={"perangkat_id": str(perangkat.id), "shift": [_shift(toko_a, shift_id, status="buka")]}
    )
    assert resp.status_code == 200

    shift = (await db_session.execute(select(Shift).where(Shift.id == shift_id))).scalar_one()
    await db_session.refresh(shift)
    assert shift.status == "tutup"


async def test_satu_transaksi_ditolak_tidak_menahan_yang_lain_dan_tercatat_di_sync_log(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id)
    metode = await buat_metode_bayar(db_session, toko_a.toko.id)
    perangkat = await buat_perangkat(db_session, toko_a.toko.id, toko_a.outlet.id)

    pid = perangkat.id
    bagus = _trx(toko_a, produk, metode, nomor="OUT1-INT-0002")
    rusak = _trx(toko_a, produk, metode, nomor="OUT1-INT-0003")
    rusak["items"][0]["produk_id"] = str(uuid.uuid4())  # produk tidak ada di server

    resp = await client.post(
        "/sync/push", headers=toko_a.headers, json={"perangkat_id": str(pid), "transaksi": [rusak, bagus]}
    )
    assert resp.status_code == 200
    status = {h["id"]: h["status"] for h in resp.json()["transaksi"]}
    assert status[bagus["id"]] == "diterima"
    assert status[rusak["id"]] == "ditolak"
    assert resp.json()["transaksi"][0]["pesan"], "alasan penolakan dikirim balik supaya HP bisa menampilkannya"

    assert await _hitung(db_session, Transaksi, Transaksi.id == uuid.UUID(bagus["id"])) == 1
    assert await _hitung(db_session, Transaksi, Transaksi.id == uuid.UUID(rusak["id"])) == 0

    log = (
        await db_session.execute(select(SyncLog).where(SyncLog.perangkat_id == pid, SyncLog.arah == "push"))
    ).scalars().all()
    assert [r.status for r in log] == ["sebagian"]


async def test_transaksi_yang_ditolak_bisa_dikirim_ulang_setelah_penyebabnya_hilang(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id)
    metode = await buat_metode_bayar(db_session, toko_a.toko.id)
    perangkat = await buat_perangkat(db_session, toko_a.toko.id, toko_a.outlet.id)

    pid, shift_id = str(perangkat.id), uuid.uuid4()  # shift belum ada di server
    shift_item = _shift(toko_a, shift_id)
    trx = _trx(toko_a, produk, metode, shift_id=shift_id, nomor="OUT1-INT-0004")
    trx_uuid = uuid.UUID(trx["id"])
    pertama = await client.post(
        "/sync/push", headers=toko_a.headers, json={"perangkat_id": pid, "transaksi": [trx]}
    )
    assert pertama.json()["transaksi"][0]["status"] == "ditolak"
    assert await _hitung(db_session, Transaksi, Transaksi.id == trx_uuid) == 0

    # HP kini mengirim shift bersama transaksinya.
    kedua = await client.post(
        "/sync/push",
        headers=toko_a.headers,
        json={"perangkat_id": pid, "shift": [shift_item], "transaksi": [trx]},
    )
    assert kedua.json()["transaksi"][0]["status"] == "diterima"
    assert await _hitung(db_session, Transaksi, Transaksi.id == trx_uuid) == 1


async def test_kas_masuk_keluar_shift_ikut_dihitung_dan_retry_tidak_menggandakan(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    from app.models.transaksi import KasShift

    produk = await buat_produk(db_session, toko_a.toko.id)
    metode = await buat_metode_bayar(db_session, toko_a.toko.id)
    perangkat = await buat_perangkat(db_session, toko_a.toko.id, toko_a.outlet.id)
    shift_id, masuk_id, keluar_id = uuid.uuid4(), uuid.uuid4(), uuid.uuid4()
    payload = {
        "perangkat_id": str(perangkat.id),
        "shift": [_shift(toko_a, shift_id)],  # modal 100.000, kas aktual 130.000
        "kas_shift": [
            {"id": str(masuk_id), "shift_id": str(shift_id), "jenis": "masuk", "jumlah": "20000", "keterangan": "Tambah modal"},
            {"id": str(keluar_id), "shift_id": str(shift_id), "jenis": "keluar", "jumlah": "5000", "keterangan": "Beli es"},
        ],
        "transaksi": [_trx(toko_a, produk, metode, shift_id=shift_id, nomor="OUT1-INT-0005")],  # tunai 30.000
    }

    for _ in range(2):
        resp = await client.post("/sync/push", headers=toko_a.headers, json=payload)
        assert resp.status_code == 200
        assert {h["status"] for h in resp.json()["kas_shift"]} <= {"diterima", "sudah_ada"}

    assert await _hitung(db_session, KasShift, KasShift.shift_id == shift_id) == 2
    shift = (await db_session.execute(select(Shift).where(Shift.id == shift_id))).scalar_one()
    await db_session.refresh(shift)
    # 100.000 modal + 30.000 penjualan tunai + 20.000 kas masuk - 5.000 kas keluar
    assert float(shift.kas_seharusnya) == 145000
    assert float(shift.selisih) == 130000 - 145000
