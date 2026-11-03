import uuid
from datetime import UTC, datetime, timedelta
from decimal import Decimal

from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.audit import SyncLog
from app.models.pelanggan import Pelanggan
from app.models.transaksi import KasShift, Shift, Transaksi
from tests.conftest import buat_metode_bayar, buat_perangkat, buat_produk


async def test_push_perangkat_tidak_terdaftar_ditolak(client: AsyncClient, toko_a) -> None:
    resp = await client.post(
        "/sync/push", headers=toko_a.headers, json={"perangkat_id": str(uuid.uuid4())}
    )
    assert resp.status_code == 404


async def test_push_transaksi_batch_idempotent(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id)
    metode = await buat_metode_bayar(db_session, toko_a.toko.id)
    perangkat = await buat_perangkat(db_session, toko_a.toko.id, toko_a.outlet.id)

    transaksi_id = str(uuid.uuid4())
    payload = {
        "perangkat_id": str(perangkat.id),
        "transaksi": [
            {
                "id": transaksi_id,
                "outlet_id": str(toko_a.outlet.id),
                "nomor_struk": "OUT1-SYNC-0001",
                "tanggal": datetime.now(UTC).isoformat(),
                "items": [
                    {"produk_id": str(produk.id), "nama_produk": produk.nama, "qty": "1", "harga_satuan": "15000"}
                ],
                "metode_bayar_id": str(metode.id),
                "total_bayar": "15000",
            }
        ],
    }

    resp1 = await client.post("/sync/push", headers=toko_a.headers, json=payload)
    assert resp1.status_code == 200
    assert resp1.json()["transaksi"][0]["status"] == "diterima"

    # Push ulang batch yang sama (device retry krn koneksi putus) - tidak
    # boleh mencatat transaksi dobel.
    resp2 = await client.post("/sync/push", headers=toko_a.headers, json=payload)
    assert resp2.status_code == 200
    assert resp2.json()["transaksi"][0]["status"] == "diterima"

    rows = (
        await db_session.execute(select(Transaksi).where(Transaksi.id == uuid.UUID(transaksi_id)))
    ).scalars().all()
    assert len(rows) == 1


async def test_push_shift_dan_kas_shift(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    perangkat = await buat_perangkat(db_session, toko_a.toko.id, toko_a.outlet.id)
    shift_id = str(uuid.uuid4())
    kas_id = str(uuid.uuid4())

    dibuka = datetime.now(UTC)
    resp = await client.post(
        "/sync/push",
        headers=toko_a.headers,
        json={
            "perangkat_id": str(perangkat.id),
            "shift": [
                {
                    "id": shift_id,
                    "outlet_id": str(toko_a.outlet.id),
                    "dibuka_pada": dibuka.isoformat(),
                    "modal_awal": "50000",
                    "status": "buka",
                }
            ],
            "kas_shift": [
                {"id": kas_id, "shift_id": shift_id, "jenis": "keluar", "jumlah": "10000", "keterangan": "Parkir"}
            ],
        },
    )
    assert resp.status_code == 200
    assert resp.json()["shift"][0]["status"] == "diterima"
    assert resp.json()["kas_shift"][0]["status"] == "diterima"

    shift_row = await db_session.get(Shift, uuid.UUID(shift_id))
    assert shift_row is not None
    assert shift_row.modal_awal == Decimal("50000")

    kas_row = await db_session.get(KasShift, uuid.UUID(kas_id))
    assert kas_row is not None

    # Push ulang shift yang sama tapi SUDAH ditutup (device kirim update
    # setelah tutup_shift) - harus terapkan update, bukan tolak/dobel.
    ditutup = dibuka + timedelta(hours=8)
    resp2 = await client.post(
        "/sync/push",
        headers=toko_a.headers,
        json={
            "perangkat_id": str(perangkat.id),
            "shift": [
                {
                    "id": shift_id,
                    "outlet_id": str(toko_a.outlet.id),
                    "dibuka_pada": dibuka.isoformat(),
                    "ditutup_pada": ditutup.isoformat(),
                    "modal_awal": "50000",
                    "kas_seharusnya": "40000",
                    "kas_aktual": "40000",
                    "selisih": "0",
                    "status": "tutup",
                }
            ],
        },
    )
    assert resp2.status_code == 200
    await db_session.refresh(shift_row)
    assert shift_row.status == "tutup"
    assert shift_row.selisih == Decimal("0")


async def test_push_pelanggan_baru(client: AsyncClient, db_session: AsyncSession, toko_a) -> None:
    perangkat = await buat_perangkat(db_session, toko_a.toko.id, toko_a.outlet.id)
    pelanggan_id = str(uuid.uuid4())

    resp = await client.post(
        "/sync/push",
        headers=toko_a.headers,
        json={
            "perangkat_id": str(perangkat.id),
            "pelanggan": [{"id": pelanggan_id, "nama": "Budi Santoso", "no_hp": "081200001111"}],
        },
    )
    assert resp.status_code == 200
    assert resp.json()["pelanggan"][0]["status"] == "diterima"

    pelanggan_row = await db_session.get(Pelanggan, uuid.UUID(pelanggan_id))
    assert pelanggan_row is not None
    assert pelanggan_row.nama == "Budi Santoso"

    # Push ulang pelanggan yang sama - idempotent, bukan dobel/error.
    resp2 = await client.post(
        "/sync/push",
        headers=toko_a.headers,
        json={
            "perangkat_id": str(perangkat.id),
            "pelanggan": [{"id": pelanggan_id, "nama": "Budi Santoso", "no_hp": "081200001111"}],
        },
    )
    assert resp2.json()["pelanggan"][0]["status"] == "sudah_ada"


async def test_pull_mengembalikan_data_master_sejak_waktu_tertentu(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    await buat_produk(db_session, toko_a.toko.id, nama="Kopi Hitam")
    perangkat = await buat_perangkat(db_session, toko_a.toko.id, toko_a.outlet.id)

    epoch_awal = datetime(1970, 1, 1, tzinfo=UTC)
    resp = await client.get(
        "/sync/pull",
        headers=toko_a.headers,
        params={"since": epoch_awal.isoformat(), "perangkat_id": str(perangkat.id)},
    )
    assert resp.status_code == 200
    body = resp.json()
    nama_produk = {p["nama"] for p in body["produk"]}
    assert "Kopi Hitam" in nama_produk
    # Toko fixture default pakai paket Gratis - fitur tingkat 1/2 (qris,
    # diskon, dst.) tidak boleh ikut terkirim.
    assert body["paket"] == "Gratis"
    assert "pos" in body["kode_fitur"]
    assert "qris" not in body["kode_fitur"]

    # Pull lagi dengan `since` = sekarang - tidak ada data baru.
    resp2 = await client.get(
        "/sync/pull",
        headers=toko_a.headers,
        params={"since": datetime.now(UTC).isoformat(), "perangkat_id": str(perangkat.id)},
    )
    assert resp2.json()["produk"] == []


async def test_push_dan_pull_tercatat_di_sync_log(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    perangkat = await buat_perangkat(db_session, toko_a.toko.id, toko_a.outlet.id)

    await client.post("/sync/push", headers=toko_a.headers, json={"perangkat_id": str(perangkat.id)})
    await client.get(
        "/sync/pull",
        headers=toko_a.headers,
        params={"since": datetime(1970, 1, 1, tzinfo=UTC).isoformat(), "perangkat_id": str(perangkat.id)},
    )

    rows = (
        await db_session.execute(select(SyncLog).where(SyncLog.perangkat_id == perangkat.id))
    ).scalars().all()
    arah = {r.arah for r in rows}
    assert arah == {"push", "pull"}
    assert all(r.status == "berhasil" for r in rows)


async def test_pull_toko_b_tidak_melihat_data_toko_a(
    client: AsyncClient, db_session: AsyncSession, toko_a, toko_b
) -> None:
    await buat_produk(db_session, toko_a.toko.id, nama="Punya Toko A")
    perangkat_b = await buat_perangkat(db_session, toko_b.toko.id, toko_b.outlet.id, device_uid="device-b")

    epoch_awal = datetime(1970, 1, 1, tzinfo=UTC)
    resp = await client.get(
        "/sync/pull",
        headers=toko_b.headers,
        params={"since": epoch_awal.isoformat(), "perangkat_id": str(perangkat_b.id)},
    )
    assert resp.json()["produk"] == []
