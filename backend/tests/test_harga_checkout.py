"""Tes integrasi checkout <-> mesin hitung harga (tahap 3a Part D) -
service charge, pembulatan, potong stok bundling, dan "jangan tolak,
cuma catat" saat total dari HP beda dgn hasil hitung ulang server."""

import uuid
from datetime import UTC, datetime
from decimal import Decimal

from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.audit import AuditLog, Notifikasi
from app.models.outlet import PengaturanOutlet
from app.models.produk import BundlingItem, Resep
from app.models.promo import Pajak
from app.models.stok import Stok
from app.models.transaksi import ItemTransaksi
from tests.conftest import buat_metode_bayar, buat_produk, buat_toko_siap_pakai


async def test_checkout_menghitung_service_charge_sebagai_tambahan_pajak(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id, harga_jual=Decimal("100000"))
    metode = await buat_metode_bayar(db_session, toko_a.toko.id)
    db_session.add(Pajak(toko_id=toko_a.toko.id, nama="Service", tipe="service", persen=Decimal("5"), urutan=1))
    await db_session.commit()

    resp = await client.post(
        "/transaksi",
        headers=toko_a.headers,
        json={
            "outlet_id": str(toko_a.outlet.id),
            "nomor_struk": "OUT1-SVC001",
            "tanggal": datetime.now(UTC).isoformat(),
            "items": [{"produk_id": str(produk.id), "nama_produk": produk.nama, "qty": "1", "harga_satuan": "100000"}],
            "metode_bayar_id": str(metode.id),
            "total_bayar": "105000",
        },
    )
    assert resp.status_code == 201
    body = resp.json()
    assert body["service"] == "5000.00"
    assert body["rincian_service"][0]["nama"] == "Service"
    assert body["total"] == "105000.00"


async def test_checkout_membulatkan_total_sesuai_pengaturan_outlet(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id, harga_jual=Decimal("10250"))
    metode = await buat_metode_bayar(db_session, toko_a.toko.id)
    db_session.add(PengaturanOutlet(outlet_id=toko_a.outlet.id, pembulatan=500))
    await db_session.commit()

    resp = await client.post(
        "/transaksi",
        headers=toko_a.headers,
        json={
            "outlet_id": str(toko_a.outlet.id),
            "nomor_struk": "OUT1-RND001",
            "tanggal": datetime.now(UTC).isoformat(),
            "items": [{"produk_id": str(produk.id), "nama_produk": produk.nama, "qty": "1", "harga_satuan": "10250"}],
            "metode_bayar_id": str(metode.id),
            "total_bayar": "10500",
        },
    )
    assert resp.status_code == 201
    body = resp.json()
    # 10250 dibulatkan ke kelipatan 500 terdekat -> 10500, selisih +250.
    assert body["pembulatan"] == "250.00"
    assert body["total"] == "10500.00"


async def test_checkout_bundling_memotong_stok_komponen_bukan_stok_bundle(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    # bundling tingkat 2 (Bisnis) - soal mekanika potong stok, bukan gating
    # (lihat tests/test_gating_fitur.py utk gating-nya).
    toko_a = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    roti = await buat_produk(db_session, toko_a.toko.id, nama="Roti", harga_jual=Decimal("0"))
    telur = await buat_produk(db_session, toko_a.toko.id, nama="Telur (bahan)", harga_jual=Decimal("0"))

    selai = await buat_produk(db_session, toko_a.toko.id, nama="Selai Kacang", harga_jual=Decimal("0"))
    selai.pakai_resep = True
    await db_session.commit()
    db_session.add(Resep(produk_id=selai.id, varian_id=None, bahan_id=telur.id, qty=Decimal("0.02")))

    paket_roti = await buat_produk(db_session, toko_a.toko.id, nama="Paket Roti Selai", harga_jual=Decimal("20000"))
    paket_roti.tipe = "bundling"
    await db_session.commit()
    db_session.add(BundlingItem(bundling_produk_id=paket_roti.id, produk_id=roti.id, varian_id=None, qty=Decimal("2")))
    db_session.add(BundlingItem(bundling_produk_id=paket_roti.id, produk_id=selai.id, varian_id=None, qty=Decimal("1")))
    await db_session.commit()

    metode = await buat_metode_bayar(db_session, toko_a.toko.id)
    resp = await client.post(
        "/transaksi",
        headers=toko_a.headers,
        json={
            "outlet_id": str(toko_a.outlet.id),
            "nomor_struk": "OUT1-BDL001",
            "tanggal": datetime.now(UTC).isoformat(),
            "items": [
                {"produk_id": str(paket_roti.id), "nama_produk": paket_roti.nama, "qty": "3", "harga_satuan": "20000"}
            ],
            "metode_bayar_id": str(metode.id),
            "total_bayar": "60000",
        },
    )
    assert resp.status_code == 201

    # Bundle sendiri TIDAK punya baris stok.
    stok_bundle = (await db_session.execute(select(Stok).where(Stok.produk_id == paket_roti.id))).scalar_one_or_none()
    assert stok_bundle is None

    # qty jual 3 x komponen roti 2 = 6 roti terpotong.
    stok_roti = (await db_session.execute(select(Stok).where(Stok.produk_id == roti.id))).scalar_one()
    assert stok_roti.jumlah == Decimal("-6")

    # Komponen selai pakai_resep -> bukan stok selai sendiri yang terpotong,
    # tapi bahan bakunya (telur): qty jual 3 x komponen selai 1 x resep 0.02 = 0.06.
    stok_selai = (await db_session.execute(select(Stok).where(Stok.produk_id == selai.id))).scalar_one_or_none()
    assert stok_selai is None
    stok_telur = (await db_session.execute(select(Stok).where(Stok.produk_id == telur.id))).scalar_one()
    assert stok_telur.jumlah == Decimal("-0.06")


async def test_push_sync_selisih_total_tidak_ditolak_tapi_dicatat(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id, harga_jual=Decimal("15000"))
    metode = await buat_metode_bayar(db_session, toko_a.toko.id)
    transaksi_id = uuid.uuid4()

    resp = await client.post(
        "/transaksi",
        headers=toko_a.headers,
        json={
            "id": str(transaksi_id),
            "outlet_id": str(toko_a.outlet.id),
            "nomor_struk": "OUT1-PUSH001",
            "tanggal": datetime.now(UTC).isoformat(),
            "items": [{"produk_id": str(produk.id), "nama_produk": produk.nama, "qty": "2", "harga_satuan": "15000"}],
            "metode_bayar_id": str(metode.id),
            "total_bayar": "35000",  # HP kira total 35.000 (beda dari hasil hitung server, 30.000).
            "total_klien": "35000",
        },
    )
    # TIDAK ditolak DAN disimpan sesuai angka HP apa adanya (tahap 3a C.2) -
    # bukan angka hitung ulang server (35000, bukan 30000).
    assert resp.status_code == 201
    body = resp.json()
    assert body["total"] == "35000.00"

    audit = (
        await db_session.execute(select(AuditLog).where(AuditLog.record_id == transaksi_id))
    ).scalar_one()
    assert audit.aksi == "checkout_selisih_harga"
    assert audit.data_lama == {"subtotal": "30000.00", "diskon": "0.00", "pajak": "0.00", "pembulatan": "0.00", "total": "35000.00"}
    assert audit.data_baru == {"subtotal": "30000.00", "diskon": "0.00", "pajak": "0.00", "pembulatan": "0.00", "total": "30000.00"}

    notif = (
        await db_session.execute(select(Notifikasi).where(Notifikasi.ref_id == transaksi_id))
    ).scalar_one()
    assert notif.jenis == "selisih_harga"


async def test_push_sync_total_klien_cocok_tidak_mencatat_apa_apa(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id, harga_jual=Decimal("15000"))
    metode = await buat_metode_bayar(db_session, toko_a.toko.id)
    transaksi_id = uuid.uuid4()

    resp = await client.post(
        "/transaksi",
        headers=toko_a.headers,
        json={
            "id": str(transaksi_id),
            "outlet_id": str(toko_a.outlet.id),
            "nomor_struk": "OUT1-PUSH002",
            "tanggal": datetime.now(UTC).isoformat(),
            "items": [{"produk_id": str(produk.id), "nama_produk": produk.nama, "qty": "2", "harga_satuan": "15000"}],
            "metode_bayar_id": str(metode.id),
            "total_bayar": "30000",
            "total_klien": "30000",
        },
    )
    assert resp.status_code == 201

    audit = (
        await db_session.execute(select(AuditLog).where(AuditLog.record_id == transaksi_id))
    ).scalar_one_or_none()
    assert audit is None


# ---------------------------------------------------------------------------
# Tahap 3a lanjutan C/D - checkout online SELALU hitung dari database,
# diskon manual butuh approval izin transaksi.diskon.
# ---------------------------------------------------------------------------


async def test_checkout_online_mengabaikan_harga_palsu_dari_body(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id, harga_jual=Decimal("15000"))
    metode = await buat_metode_bayar(db_session, toko_a.toko.id)

    resp = await client.post(
        "/transaksi",
        headers=toko_a.headers,
        json={
            "outlet_id": str(toko_a.outlet.id),
            "nomor_struk": "OUT1-FAKE001",
            "tanggal": datetime.now(UTC).isoformat(),
            # harga_satuan dipalsukan jadi Rp1 - server WAJIB mengabaikannya.
            "items": [{"produk_id": str(produk.id), "nama_produk": produk.nama, "qty": "2", "harga_satuan": "1"}],
            "metode_bayar_id": str(metode.id),
            "total_bayar": "30000",
        },
    )
    assert resp.status_code == 201
    body = resp.json()
    assert body["subtotal"] == "30000.00"  # 2 x 15000 (Produk.harga_jual di database), bukan 2 x 1

    item = (await db_session.execute(select(ItemTransaksi))).scalars().one()
    assert item.harga_satuan == Decimal("15000")


async def test_checkout_online_diskon_manual_tanpa_approval_ditolak_403(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id, harga_jual=Decimal("15000"))
    metode = await buat_metode_bayar(db_session, toko_a.toko.id)

    resp = await client.post(
        "/transaksi",
        headers=toko_a.headers,
        json={
            "outlet_id": str(toko_a.outlet.id),
            "nomor_struk": "OUT1-DISC001",
            "tanggal": datetime.now(UTC).isoformat(),
            "items": [
                {"produk_id": str(produk.id), "nama_produk": produk.nama, "qty": "1", "harga_satuan": "15000", "diskon": "5000"}
            ],
            "metode_bayar_id": str(metode.id),
            "total_bayar": "10000",
            # diskon_manual_disetujui_oleh TIDAK diisi.
        },
    )
    assert resp.status_code == 403
    assert resp.json()["detail"]["kode"] == "diskon_manual_tidak_diizinkan"


async def test_checkout_online_diskon_manual_melebihi_subtotal_baris_ditolak_403(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id, harga_jual=Decimal("15000"))
    metode = await buat_metode_bayar(db_session, toko_a.toko.id)

    resp = await client.post(
        "/transaksi",
        headers=toko_a.headers,
        json={
            "outlet_id": str(toko_a.outlet.id),
            "nomor_struk": "OUT1-DISC002",
            "tanggal": datetime.now(UTC).isoformat(),
            "items": [
                {"produk_id": str(produk.id), "nama_produk": produk.nama, "qty": "1", "harga_satuan": "15000", "diskon": "99999"}
            ],
            "metode_bayar_id": str(metode.id),
            "total_bayar": "1",
            "diskon_manual_disetujui_oleh": str(toko_a.pengguna.id),
        },
    )
    assert resp.status_code == 403
    assert resp.json()["detail"]["kode"] == "diskon_manual_tidak_valid"


async def test_checkout_online_diskon_manual_dengan_approval_sah_diterima(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    # toko_a Owner secara default punya izin transaksi.diskon (seed).
    produk = await buat_produk(db_session, toko_a.toko.id, harga_jual=Decimal("15000"))
    metode = await buat_metode_bayar(db_session, toko_a.toko.id)

    resp = await client.post(
        "/transaksi",
        headers=toko_a.headers,
        json={
            "outlet_id": str(toko_a.outlet.id),
            "nomor_struk": "OUT1-DISC003",
            "tanggal": datetime.now(UTC).isoformat(),
            "items": [
                {"produk_id": str(produk.id), "nama_produk": produk.nama, "qty": "1", "harga_satuan": "15000", "diskon": "5000"}
            ],
            "metode_bayar_id": str(metode.id),
            "total_bayar": "10000",
            "diskon_manual_disetujui_oleh": str(toko_a.pengguna.id),
        },
    )
    assert resp.status_code == 201
    body = resp.json()
    assert body["subtotal"] == "10000.00"  # 15000 - 5000

    audit = (
        await db_session.execute(
            select(AuditLog).where(AuditLog.record_id == uuid.UUID(body["id"]), AuditLog.aksi == "diskon_manual_disetujui")
        )
    ).scalar_one()
    assert audit.data_baru["diskon"] == "5000"
    assert audit.data_baru["disetujui_oleh"] == str(toko_a.pengguna.id)


async def test_checkout_online_kasir_tidak_bisa_approve_diskon_sendiri(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_role="Kasir")
    produk = await buat_produk(db_session, toko.toko.id, harga_jual=Decimal("15000"))
    metode = await buat_metode_bayar(db_session, toko.toko.id)

    resp = await client.post(
        "/transaksi",
        headers=toko.headers,
        json={
            "outlet_id": str(toko.outlet.id),
            "nomor_struk": "OUT1-DISC004",
            "tanggal": datetime.now(UTC).isoformat(),
            "items": [
                {"produk_id": str(produk.id), "nama_produk": produk.nama, "qty": "1", "harga_satuan": "15000", "diskon": "5000"}
            ],
            "metode_bayar_id": str(metode.id),
            "total_bayar": "10000",
            # Kasir mencoba approve diskonnya sendiri - Kasir tidak punya izin transaksi.diskon.
            "diskon_manual_disetujui_oleh": str(toko.pengguna.id),
        },
    )
    assert resp.status_code == 403
    assert resp.json()["detail"]["kode"] == "diskon_manual_tidak_diizinkan"


async def test_push_offline_diskon_manual_tanpa_approval_tetap_disimpan_tapi_ditandai(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id, harga_jual=Decimal("15000"))
    metode = await buat_metode_bayar(db_session, toko_a.toko.id)
    transaksi_id = uuid.uuid4()

    resp = await client.post(
        "/transaksi",
        headers=toko_a.headers,
        json={
            "id": str(transaksi_id),
            "outlet_id": str(toko_a.outlet.id),
            "nomor_struk": "OUT1-PUSH003",
            "tanggal": datetime.now(UTC).isoformat(),
            "items": [
                {"produk_id": str(produk.id), "nama_produk": produk.nama, "qty": "1", "harga_satuan": "15000", "diskon": "5000"}
            ],
            "metode_bayar_id": str(metode.id),
            "total_bayar": "10000",
            "subtotal_klien": "15000",
            "total_klien": "10000",
            # Tanpa diskon_manual_disetujui_oleh - sudah terjadi offline, TETAP disimpan.
        },
    )
    assert resp.status_code == 201
    body = resp.json()
    assert body["subtotal"] == "15000.00"
    assert body["total"] == "10000.00"

    item = (await db_session.execute(select(ItemTransaksi))).scalars().one()
    assert item.diskon == Decimal("5000")  # diskon manual tetap tersimpan apa adanya

    audit = (
        await db_session.execute(
            select(AuditLog).where(
                AuditLog.record_id == transaksi_id, AuditLog.aksi == "diskon_manual_tanpa_approval_sah"
            )
        )
    ).scalar_one()
    assert audit is not None

    notif = (
        await db_session.execute(
            select(Notifikasi).where(Notifikasi.ref_id == transaksi_id, Notifikasi.jenis == "diskon_tanpa_approval")
        )
    ).scalar_one()
    assert notif is not None


async def test_push_offline_kas_seharusnya_pakai_angka_tersimpan_bukan_hitung_ulang_server(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    # C.3 - kas_seharusnya shift harus memakai total_bayar yang TERSIMPAN
    # (uang sungguhan di laci), bukan hasil hitung ulang server - walau
    # total_klien dari HP berbeda dari hitung ulang server.
    produk = await buat_produk(db_session, toko_a.toko.id, harga_jual=Decimal("15000"))
    tunai = await buat_metode_bayar(db_session, toko_a.toko.id, tipe="tunai")

    resp_buka = await client.post(
        "/shift/buka", headers=toko_a.headers, json={"outlet_id": str(toko_a.outlet.id), "modal_awal": "0"}
    )
    shift_id = resp_buka.json()["id"]

    await client.post(
        "/transaksi",
        headers=toko_a.headers,
        json={
            "id": str(uuid.uuid4()),
            "outlet_id": str(toko_a.outlet.id),
            "shift_id": shift_id,
            "nomor_struk": "OUT1-PUSH004",
            "tanggal": datetime.now(UTC).isoformat(),
            "items": [{"produk_id": str(produk.id), "nama_produk": produk.nama, "qty": "2", "harga_satuan": "15000"}],
            "metode_bayar_id": str(tunai.id),
            # HP kira totalnya 50.000 (beda dari hitung ulang server 30.000) - tapi uang yg
            # BENAR2 diterima kasir (tunai, masuk laci) adalah 50.000 ini.
            "total_bayar": "50000",
            "total_klien": "50000",
        },
    )

    resp_tutup = await client.post(f"/shift/{shift_id}/tutup", headers=toko_a.headers, json={"kas_aktual": "50000"})
    assert resp_tutup.status_code == 200
    body = resp_tutup.json()
    assert body["kas_seharusnya"] == "50000.00"
    assert body["selisih"] == "0.00"
