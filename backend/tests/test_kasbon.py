"""Tahap 3b-1: kasbon (bayar dengan utang), DP, cicilan, pelunasan -
skenario di luar yang sudah dicek test_checkout.py (fitur_terkunci dasar)."""

import uuid
from datetime import UTC, datetime, timedelta
from decimal import Decimal

from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.audit import AuditLog, Notifikasi
from app.models.transaksi import ItemTransaksi, Transaksi
from tests.conftest import buat_metode_bayar, buat_perangkat, buat_produk, buat_toko_siap_pakai


async def _buka_shift(client: AsyncClient, toko, *, modal_awal: str = "0") -> uuid.UUID:
    resp = await client.post(
        "/shift/buka", headers=toko.headers, json={"outlet_id": str(toko.outlet.id), "modal_awal": modal_awal}
    )
    assert resp.status_code == 201
    return uuid.UUID(resp.json()["id"])


async def _tutup_shift(client: AsyncClient, toko, shift_id: uuid.UUID, *, kas_aktual: str) -> dict:
    resp = await client.post(
        f"/shift/{shift_id}/tutup", headers=toko.headers, json={"kas_aktual": kas_aktual}
    )
    assert resp.status_code == 200
    return resp.json()


async def _buat_pelanggan(client: AsyncClient, toko, *, nama: str, batas_kasbon: str | None = None) -> uuid.UUID:
    body = {"nama": nama, "no_hp": "0812000000"}
    if batas_kasbon is not None:
        body["batas_kasbon"] = batas_kasbon
    resp = await client.post("/pelanggan", headers=toko.headers, json=body)
    assert resp.status_code == 201
    return uuid.UUID(resp.json()["id"])


async def test_kasbon_tanpa_pelanggan_ditolak(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Pro")
    produk = await buat_produk(db_session, toko.toko.id, harga_jual=Decimal("15000"))
    metode = await buat_metode_bayar(db_session, toko.toko.id)
    shift_id = await _buka_shift(client, toko)

    resp = await client.post(
        "/transaksi",
        headers=toko.headers,
        json={
            "outlet_id": str(toko.outlet.id),
            "shift_id": str(shift_id),
            "nomor_struk": "KSB-0001",
            "tanggal": datetime.now(UTC).isoformat(),
            "items": [
                {"produk_id": str(produk.id), "nama_produk": produk.nama, "qty": "1", "harga_satuan": "15000"}
            ],
            "metode_bayar_id": str(metode.id),
            "total_bayar": "0",
        },
    )
    assert resp.status_code == 400
    assert resp.json()["detail"]["kode"] == "kasbon_butuh_pelanggan"


async def test_kasbon_toko_gratis_ditolak_fitur_terkunci(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id, harga_jual=Decimal("15000"))
    metode = await buat_metode_bayar(db_session, toko_a.toko.id)
    pelanggan_id = await _buat_pelanggan(client, toko_a, nama="Budi")

    resp = await client.post(
        "/transaksi",
        headers=toko_a.headers,
        json={
            "outlet_id": str(toko_a.outlet.id),
            "pelanggan_id": str(pelanggan_id),
            "nomor_struk": "KSB-0002",
            "tanggal": datetime.now(UTC).isoformat(),
            "items": [
                {"produk_id": str(produk.id), "nama_produk": produk.nama, "qty": "1", "harga_satuan": "15000"}
            ],
            "metode_bayar_id": str(metode.id),
            "total_bayar": "0",
        },
    )
    assert resp.status_code == 403
    assert resp.json()["detail"]["kode"] == "fitur_terkunci"
    assert resp.json()["detail"]["fitur"] == "kasbon"


async def test_pro_tanpa_dp_kasbon_menolak_dp_tapi_boleh_kasbon_bayar_nol(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Pro")
    produk = await buat_produk(db_session, toko.toko.id, harga_jual=Decimal("15000"))
    metode = await buat_metode_bayar(db_session, toko.toko.id)
    pelanggan_id = await _buat_pelanggan(client, toko, nama="Budi")

    # DP (0 < bayar < total) ditolak - Pro cuma punya 'kasbon', bukan 'dp_kasbon'.
    resp_dp = await client.post(
        "/transaksi",
        headers=toko.headers,
        json={
            "outlet_id": str(toko.outlet.id),
            "pelanggan_id": str(pelanggan_id),
            "nomor_struk": "KSB-0003",
            "tanggal": datetime.now(UTC).isoformat(),
            "items": [
                {"produk_id": str(produk.id), "nama_produk": produk.nama, "qty": "1", "harga_satuan": "15000"}
            ],
            "metode_bayar_id": str(metode.id),
            "total_bayar": "5000",
        },
    )
    assert resp_dp.status_code == 403
    assert resp_dp.json()["detail"]["kode"] == "fitur_terkunci"
    assert resp_dp.json()["detail"]["fitur"] == "dp_kasbon"

    # Kasbon bayar 0 di awal TETAP boleh (hanya DP yang butuh dp_kasbon).
    resp_nol = await client.post(
        "/transaksi",
        headers=toko.headers,
        json={
            "outlet_id": str(toko.outlet.id),
            "pelanggan_id": str(pelanggan_id),
            "nomor_struk": "KSB-0004",
            "tanggal": datetime.now(UTC).isoformat(),
            "items": [
                {"produk_id": str(produk.id), "nama_produk": produk.nama, "qty": "1", "harga_satuan": "15000"}
            ],
            "metode_bayar_id": str(metode.id),
            "total_bayar": "0",
        },
    )
    assert resp_nol.status_code == 201
    body = resp_nol.json()
    assert body["status_bayar"] == "belum_bayar"
    assert body["sisa_tagihan"] == "15000.00"
    assert body["jatuh_tempo"] is not None


async def test_cicilan_di_shift_lain_masuk_kas_shift_penerima(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    produk = await buat_produk(db_session, toko.toko.id, harga_jual=Decimal("50000"))
    metode = await buat_metode_bayar(db_session, toko.toko.id)
    pelanggan_id = await _buat_pelanggan(client, toko, nama="Citra")

    shift1_id = await _buka_shift(client, toko)
    resp = await client.post(
        "/transaksi",
        headers=toko.headers,
        json={
            "outlet_id": str(toko.outlet.id),
            "shift_id": str(shift1_id),
            "pelanggan_id": str(pelanggan_id),
            "nomor_struk": "KSB-0005",
            "tanggal": datetime.now(UTC).isoformat(),
            "items": [
                {"produk_id": str(produk.id), "nama_produk": produk.nama, "qty": "1", "harga_satuan": "50000"}
            ],
            "metode_bayar_id": str(metode.id),
            "total_bayar": "20000",  # DP
        },
    )
    assert resp.status_code == 201
    transaksi_id = resp.json()["id"]
    assert resp.json()["sisa_tagihan"] == "30000.00"

    await _tutup_shift(client, toko, shift1_id, kas_aktual="20000")
    shift2_id = await _buka_shift(client, toko)

    bayar_resp = await client.post(
        f"/transaksi/{transaksi_id}/pembayaran",
        headers=toko.headers,
        json={"shift_id": str(shift2_id), "metode_bayar_id": str(metode.id), "jumlah": "30000"},
    )
    assert bayar_resp.status_code == 201
    assert bayar_resp.json()["jenis"] == "pelunasan"
    assert bayar_resp.json()["sisa_tagihan"] == "0.00"
    assert bayar_resp.json()["status_bayar"] == "lunas"

    laporan_shift1 = await client.get(f"/laporan/shift/{shift1_id}", headers=toko.headers)
    assert laporan_shift1.json()["kas_seharusnya"] == "20000.00"

    laporan_shift2 = await client.get(f"/laporan/shift/{shift2_id}", headers=toko.headers)
    assert laporan_shift2.json()["kas_seharusnya"] == "30000.00"


async def test_dua_pelunasan_offline_melebihi_sisa_tetap_tersimpan_dan_notifikasi(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    produk = await buat_produk(db_session, toko.toko.id, harga_jual=Decimal("50000"))
    metode = await buat_metode_bayar(db_session, toko.toko.id)
    pelanggan_id = await _buat_pelanggan(client, toko, nama="Dedi")
    perangkat = await buat_perangkat(db_session, toko.toko.id, toko.outlet.id, device_uid="hp-dedi")

    shift_id = await _buka_shift(client, toko)
    resp = await client.post(
        "/transaksi",
        headers=toko.headers,
        json={
            "outlet_id": str(toko.outlet.id),
            "shift_id": str(shift_id),
            "pelanggan_id": str(pelanggan_id),
            "nomor_struk": "KSB-0006",
            "tanggal": datetime.now(UTC).isoformat(),
            "items": [
                {"produk_id": str(produk.id), "nama_produk": produk.nama, "qty": "1", "harga_satuan": "50000"}
            ],
            "metode_bayar_id": str(metode.id),
            "total_bayar": "0",
        },
    )
    assert resp.status_code == 201
    transaksi_id = resp.json()["id"]

    id1, id2 = str(uuid.uuid4()), str(uuid.uuid4())
    push_resp = await client.post(
        "/sync/push",
        headers=toko.headers,
        json={
            "perangkat_id": str(perangkat.id),
            "pembayaran": [
                {
                    "id": id1,
                    "transaksi_id": transaksi_id,
                    "shift_id": str(shift_id),
                    "metode_bayar_id": str(metode.id),
                    "jumlah": "30000",
                },
                {
                    "id": id2,
                    "transaksi_id": transaksi_id,
                    "shift_id": str(shift_id),
                    "metode_bayar_id": str(metode.id),
                    "jumlah": "30000",
                },
            ],
        },
    )
    assert push_resp.status_code == 200
    hasil = push_resp.json()["pembayaran"]
    assert [h["status"] for h in hasil] == ["diterima", "diterima"]

    transaksi = await db_session.get(Transaksi, uuid.UUID(transaksi_id))
    await db_session.refresh(transaksi)
    assert transaksi.sisa_tagihan == Decimal("0.00") or Decimal(str(transaksi.sisa_tagihan)) == Decimal("0")
    assert transaksi.status_bayar == "lunas"

    lebih_bayar_log = (
        await db_session.execute(
            select(AuditLog).where(AuditLog.aksi == "pembayaran_lebih_bayar", AuditLog.record_id == transaksi.id)
        )
    ).scalars().all()
    assert len(lebih_bayar_log) == 1

    notif = (
        await db_session.execute(
            select(Notifikasi).where(Notifikasi.jenis == "pembayaran_lebih_bayar", Notifikasi.ref_id == transaksi.id)
        )
    ).scalars().all()
    assert len(notif) == 1


async def test_void_kasbon_sudah_dicicil_ditolak(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    produk = await buat_produk(db_session, toko.toko.id, harga_jual=Decimal("50000"))
    metode = await buat_metode_bayar(db_session, toko.toko.id)
    pelanggan_id = await _buat_pelanggan(client, toko, nama="Eka")
    shift_id = await _buka_shift(client, toko)

    # DP > 0 - sudah ada baris Pembayaran sejak checkout.
    resp = await client.post(
        "/transaksi",
        headers=toko.headers,
        json={
            "outlet_id": str(toko.outlet.id),
            "shift_id": str(shift_id),
            "pelanggan_id": str(pelanggan_id),
            "nomor_struk": "KSB-0007",
            "tanggal": datetime.now(UTC).isoformat(),
            "items": [
                {"produk_id": str(produk.id), "nama_produk": produk.nama, "qty": "1", "harga_satuan": "50000"}
            ],
            "metode_bayar_id": str(metode.id),
            "total_bayar": "20000",
        },
    )
    assert resp.status_code == 201
    transaksi_id = resp.json()["id"]

    void_resp = await client.post(
        f"/transaksi/{transaksi_id}/void", headers=toko.headers, json={"alasan": "coba void"}
    )
    assert void_resp.status_code == 409

    # Sanity: kasbon bayar 0 (belum ada pembayaran sama sekali) tetap boleh void.
    resp2 = await client.post(
        "/transaksi",
        headers=toko.headers,
        json={
            "outlet_id": str(toko.outlet.id),
            "shift_id": str(shift_id),
            "pelanggan_id": str(pelanggan_id),
            "nomor_struk": "KSB-0008",
            "tanggal": datetime.now(UTC).isoformat(),
            "items": [
                {"produk_id": str(produk.id), "nama_produk": produk.nama, "qty": "1", "harga_satuan": "50000"}
            ],
            "metode_bayar_id": str(metode.id),
            "total_bayar": "0",
        },
    )
    assert resp2.status_code == 201
    void_resp2 = await client.post(
        f"/transaksi/{resp2.json()['id']}/void", headers=toko.headers, json={"alasan": "coba void lagi"}
    )
    assert void_resp2.status_code == 200


async def test_refund_kasbon_mengurangi_sisa_dulu(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    produk = await buat_produk(db_session, toko.toko.id, harga_jual=Decimal("10000"))
    metode = await buat_metode_bayar(db_session, toko.toko.id)
    pelanggan_id = await _buat_pelanggan(client, toko, nama="Fani")
    shift_id = await _buka_shift(client, toko)

    resp = await client.post(
        "/transaksi",
        headers=toko.headers,
        json={
            "outlet_id": str(toko.outlet.id),
            "shift_id": str(shift_id),
            "pelanggan_id": str(pelanggan_id),
            "nomor_struk": "KSB-0009",
            "tanggal": datetime.now(UTC).isoformat(),
            "items": [
                {"produk_id": str(produk.id), "nama_produk": produk.nama, "qty": "5", "harga_satuan": "10000"}
            ],
            "metode_bayar_id": str(metode.id),
            "total_bayar": "0",
        },
    )
    assert resp.status_code == 201
    transaksi_id = resp.json()["id"]
    assert resp.json()["sisa_tagihan"] == "50000.00"

    items = (
        await db_session.execute(
            select(ItemTransaksi).where(ItemTransaksi.transaksi_id == uuid.UUID(transaksi_id))
        )
    ).scalars().all()
    item_id = items[0].id

    # Refund 2 dari 5 qty (20000) - masih < sisa_tagihan (50000) -> SELURUHNYA mengurangi sisa, kas_dikembalikan 0.
    refund1 = await client.post(
        f"/transaksi/{transaksi_id}/refund",
        headers=toko.headers,
        json={
            "alasan": "rusak sebagian", "kembalikan_stok": True, "shift_id": str(shift_id),
            "items": [{"item_transaksi_id": str(item_id), "qty": "2"}],
        },
    )
    assert refund1.status_code == 201
    body1 = refund1.json()
    assert body1["total"] == "20000.00"
    assert body1["kas_dikembalikan"] == "0.00"
    assert body1["sisa_tagihan"] == "30000.00"

    # Refund 3 qty sisanya (30000) == sisa_tagihan (30000) -> semua mengurangi sisa, tetap kas_dikembalikan 0, lunas.
    refund2 = await client.post(
        f"/transaksi/{transaksi_id}/refund",
        headers=toko.headers,
        json={
            "alasan": "rusak sisanya", "kembalikan_stok": True, "shift_id": str(shift_id),
            "items": [{"item_transaksi_id": str(item_id), "qty": "3"}],
        },
    )
    assert refund2.status_code == 201
    body2 = refund2.json()
    assert body2["total"] == "30000.00"
    assert body2["kas_dikembalikan"] == "0.00"
    assert body2["sisa_tagihan"] == "0.00"
    assert body2["status_transaksi"] == "refund"


async def test_batas_kasbon_ditolak_saat_terlampaui(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Pro")
    produk = await buat_produk(db_session, toko.toko.id, harga_jual=Decimal("5000"))
    metode = await buat_metode_bayar(db_session, toko.toko.id)
    pelanggan_id = await _buat_pelanggan(client, toko, nama="Gita", batas_kasbon="10000")
    shift_id = await _buka_shift(client, toko)

    resp1 = await client.post(
        "/transaksi",
        headers=toko.headers,
        json={
            "outlet_id": str(toko.outlet.id),
            "shift_id": str(shift_id),
            "pelanggan_id": str(pelanggan_id),
            "nomor_struk": "KSB-0010",
            "tanggal": datetime.now(UTC).isoformat(),
            "items": [
                {"produk_id": str(produk.id), "nama_produk": produk.nama, "qty": "1", "harga_satuan": "5000"}
            ],
            "metode_bayar_id": str(metode.id),
            "total_bayar": "0",
        },
    )
    assert resp1.status_code == 201  # utang jadi 5000, masih <= batas 10000

    resp2 = await client.post(
        "/transaksi",
        headers=toko.headers,
        json={
            "outlet_id": str(toko.outlet.id),
            "shift_id": str(shift_id),
            "pelanggan_id": str(pelanggan_id),
            "nomor_struk": "KSB-0011",
            "tanggal": datetime.now(UTC).isoformat(),
            "items": [
                {"produk_id": str(produk.id), "nama_produk": produk.nama, "qty": "2", "harga_satuan": "5000"}
            ],
            "metode_bayar_id": str(metode.id),
            "total_bayar": "0",
        },
    )
    assert resp2.status_code == 403  # 5000 + 10000 = 15000 > batas 10000
    assert resp2.json()["detail"]["kode"] == "batas_kasbon_terlampaui"


async def test_batas_kasbon_terlampaui_push_offline_tetap_diterima(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    # Tahap 4 bagian A.2: push offline (body.id terisi) sudah terjadi di HP
    # (barang sudah dibawa pelanggan) - beda dari online, batas_kasbon yang
    # terlampaui TIDAK menolak transaksi, cuma dicatat audit_log + notifikasi.
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Pro")
    produk = await buat_produk(db_session, toko.toko.id, harga_jual=Decimal("5000"))
    metode = await buat_metode_bayar(db_session, toko.toko.id)
    pelanggan_id = await _buat_pelanggan(client, toko, nama="Hari", batas_kasbon="10000")
    shift_id = await _buka_shift(client, toko)

    resp1 = await client.post(
        "/transaksi",
        headers=toko.headers,
        json={
            "outlet_id": str(toko.outlet.id),
            "shift_id": str(shift_id),
            "pelanggan_id": str(pelanggan_id),
            "nomor_struk": "KSB-0016",
            "tanggal": datetime.now(UTC).isoformat(),
            "items": [
                {"produk_id": str(produk.id), "nama_produk": produk.nama, "qty": "1", "harga_satuan": "5000"}
            ],
            "metode_bayar_id": str(metode.id),
            "total_bayar": "0",
        },
    )
    assert resp1.status_code == 201  # utang jadi 5000, masih <= batas 10000

    transaksi_offline_id = str(uuid.uuid4())
    resp2 = await client.post(
        "/transaksi",
        headers=toko.headers,
        json={
            "id": transaksi_offline_id,
            "outlet_id": str(toko.outlet.id),
            "shift_id": str(shift_id),
            "pelanggan_id": str(pelanggan_id),
            "nomor_struk": "KSB-0017",
            "tanggal": datetime.now(UTC).isoformat(),
            "items": [
                {"produk_id": str(produk.id), "nama_produk": produk.nama, "qty": "2", "harga_satuan": "5000"}
            ],
            "metode_bayar_id": str(metode.id),
            "total_bayar": "0",
        },
    )
    assert resp2.status_code == 201  # push offline - tetap diterima walau 5000+10000 > batas 10000
    assert resp2.json()["sisa_tagihan"] == "10000.00"

    transaksi = await db_session.get(Transaksi, uuid.UUID(transaksi_offline_id))
    assert transaksi is not None
    assert transaksi.sisa_tagihan == Decimal("10000.00")

    log = (
        await db_session.execute(
            select(AuditLog).where(
                AuditLog.aksi == "kasbon_lewati_batas", AuditLog.record_id == transaksi.id
            )
        )
    ).scalar_one_or_none()
    assert log is not None

    notif = (
        await db_session.execute(
            select(Notifikasi).where(
                Notifikasi.jenis == "kasbon_lewati_batas", Notifikasi.ref_id == transaksi.id
            )
        )
    ).scalar_one_or_none()
    assert notif is not None


async def test_laporan_piutang_per_pelanggan_dan_umur(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    produk = await buat_produk(db_session, toko.toko.id, harga_jual=Decimal("10000"))
    metode = await buat_metode_bayar(db_session, toko.toko.id)
    pelanggan_h = await _buat_pelanggan(client, toko, nama="Hadi")
    pelanggan_i = await _buat_pelanggan(client, toko, nama="Indah")
    shift_id = await _buka_shift(client, toko)

    async def _checkout(nomor: str, pelanggan_id: uuid.UUID) -> uuid.UUID:
        resp = await client.post(
            "/transaksi",
            headers=toko.headers,
            json={
                "outlet_id": str(toko.outlet.id),
                "shift_id": str(shift_id),
                "pelanggan_id": str(pelanggan_id),
                "nomor_struk": nomor,
                "tanggal": datetime.now(UTC).isoformat(),
                "items": [
                    {"produk_id": str(produk.id), "nama_produk": produk.nama, "qty": "1", "harga_satuan": "10000"}
                ],
                "metode_bayar_id": str(metode.id),
                "total_bayar": "0",
            },
        )
        assert resp.status_code == 201
        return uuid.UUID(resp.json()["id"])

    t1 = await _checkout("KSB-0012", pelanggan_h)
    t2 = await _checkout("KSB-0013", pelanggan_h)
    t3 = await _checkout("KSB-0014", pelanggan_i)

    # Paksa jatuh_tempo t1 sudah lewat 10 hari, t2 masih jauh di depan,
    # t3 lewat 40 hari - supaya umur_hari & lewat_jatuh_tempo bisa dicek.
    hari_ini = datetime.now(UTC).date()
    transaksi1 = await db_session.get(Transaksi, t1)
    transaksi1.jatuh_tempo = hari_ini - timedelta(days=10)
    transaksi2 = await db_session.get(Transaksi, t2)
    transaksi2.jatuh_tempo = hari_ini + timedelta(days=5)
    transaksi3 = await db_session.get(Transaksi, t3)
    transaksi3.jatuh_tempo = hari_ini - timedelta(days=40)
    await db_session.commit()

    resp = await client.get("/laporan/piutang", headers=toko.headers)
    assert resp.status_code == 200
    body = resp.json()

    assert body["jumlah_pelanggan"] == 2
    assert body["total_piutang"] == "30000.00"
    assert body["jumlah_lewat_jatuh_tempo"] == 2

    per_pelanggan = {p["pelanggan_id"]: p for p in body["pelanggan"]}
    hadi = per_pelanggan[str(pelanggan_h)]
    assert hadi["total_utang"] == "20000.00"
    assert hadi["jumlah_transaksi"] == 2
    assert hadi["jatuh_tempo_terdekat"] == str(hari_ini - timedelta(days=10))
    assert hadi["lewat_jatuh_tempo"] is True
    assert hadi["umur_hari"] == 10

    indah = per_pelanggan[str(pelanggan_i)]
    assert indah["total_utang"] == "10000.00"
    assert indah["umur_hari"] == 40


async def test_laporan_pemisahan_penjualan_vs_kas_diterima(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    produk = await buat_produk(db_session, toko.toko.id, harga_jual=Decimal("50000"))
    metode = await buat_metode_bayar(db_session, toko.toko.id)
    pelanggan_id = await _buat_pelanggan(client, toko, nama="Joko")
    shift_id = await _buka_shift(client, toko)

    hari1 = datetime(2026, 1, 10, 10, 0, tzinfo=UTC)
    hari2 = datetime(2026, 1, 20, 10, 0, tzinfo=UTC)

    resp = await client.post(
        "/transaksi",
        headers=toko.headers,
        json={
            "outlet_id": str(toko.outlet.id),
            "shift_id": str(shift_id),
            "pelanggan_id": str(pelanggan_id),
            "nomor_struk": "KSB-0015",
            "tanggal": hari1.isoformat(),
            "items": [
                {"produk_id": str(produk.id), "nama_produk": produk.nama, "qty": "1", "harga_satuan": "50000"}
            ],
            "metode_bayar_id": str(metode.id),
            "total_bayar": "20000",  # DP, dibayar_pada = hari1 (tanggal transaksi)
        },
    )
    assert resp.status_code == 201
    transaksi_id = resp.json()["id"]

    # Cicilan pelunasan diterima di hari2 (bulan sama supaya tidak lewat batas laporan_dasar Gratis - toko ini Bisnis, tidak dibatasi).
    bayar_resp = await client.post(
        f"/transaksi/{transaksi_id}/pembayaran",
        headers=toko.headers,
        json={
            "shift_id": str(shift_id), "metode_bayar_id": str(metode.id), "jumlah": "30000",
            "dibayar_pada": hari2.isoformat(),
        },
    )
    assert bayar_resp.status_code == 201

    laporan_hari1 = await client.get(
        "/laporan/penjualan",
        headers=toko.headers,
        params={"dari": "2026-01-10T00:00:00Z", "sampai": "2026-01-11T00:00:00Z"},
    )
    body1 = laporan_hari1.json()
    assert body1["penjualan_bersih"] == "50000.00"  # nilai transaksi penuh, walau baru dibayar 20000
    assert body1["kas_diterima"] == "20000.00"  # cuma DP yang benar2 diterima hari itu

    laporan_hari2 = await client.get(
        "/laporan/penjualan",
        headers=toko.headers,
        params={"dari": "2026-01-20T00:00:00Z", "sampai": "2026-01-21T00:00:00Z"},
    )
    body2 = laporan_hari2.json()
    assert Decimal(body2["penjualan_bersih"]) == Decimal("0")  # tidak ada transaksi BARU hari itu
    assert body2["kas_diterima"] == "30000.00"  # pelunasan dari transaksi lama diterima hari itu
