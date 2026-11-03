"""Tes gating paket (tahap 2 bagian B) - utk SETIAP baris di
app/core/fitur_map.py yang punya endpoint (`endpoint_tergate()`): toko
paket Gratis WAJIB ditolak 403 dgn body `{"kode": "fitur_terkunci",
"fitur": <kode>, "paket_minimal": <nama>}`, toko paket Bisnis WAJIB
diterima (bukan 403 fitur_terkunci). Dibuat dari fitur_map langsung
(bukan daftar manual) - baris baru yg ditambahkan ke fitur_map tanpa
setup di sini akan gagal loud (KeyError), bukan diam-diam terlewat."""

from collections.abc import Awaitable, Callable

import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.fitur_map import endpoint_tergate
from tests.conftest import buat_perangkat, buat_produk, buat_toko_siap_pakai

# Tiap entri: (method, url_builder, body_builder) - keduanya terima
# (toko, extra) dan mengembalikan nilai siap pakai. `extra` adalah dict
# hasil setup tambahan (produk, dsb) yg dibuat per-toko di _siapkan().
_SetupFn = Callable[[AsyncSession, object], Awaitable[dict]]


async def _setup_resep(db: AsyncSession, toko) -> dict:
    produk = await buat_produk(db, toko.toko.id, nama="Nasi Goreng")
    bahan = await buat_produk(db, toko.toko.id, nama="Beras")
    return {
        "method": "POST", "url": f"/produk/{produk.id}/resep",
        "json": {"bahan_id": str(bahan.id), "qty": "1"},
    }


async def _setup_bundling(db: AsyncSession, toko) -> dict:
    paket_produk = await buat_produk(db, toko.toko.id, nama="Paket Hemat")
    isi = await buat_produk(db, toko.toko.id, nama="Isi Paket")
    return {
        "method": "POST", "url": f"/produk/{paket_produk.id}/bundling",
        "json": {"produk_id": str(isi.id), "qty": "1"},
    }


async def _setup_harga_grosir(db: AsyncSession, toko) -> dict:
    produk = await buat_produk(db, toko.toko.id, nama="Beras 5kg")
    return {
        "method": "POST", "url": f"/produk/{produk.id}/harga-grosir",
        "json": {"min_qty": "5", "harga": "1000"},
    }


async def _setup_diskon(db: AsyncSession, toko) -> dict:
    return {
        "method": "POST", "url": "/promo",
        "json": {"nama": "Diskon Test", "tipe": "persen", "nilai": "10"},
    }


async def _setup_tipe_order(db: AsyncSession, toko) -> dict:
    return {
        "method": "POST", "url": "/tipe-order",
        "json": {"nama": "Dine In", "kanal": "makan_di_tempat"},
    }


async def _setup_kelola_karyawan(db: AsyncSession, toko) -> dict:
    return {
        "method": "POST", "url": "/pengguna",
        "json": {"role_id": str(toko.role.id), "nama": "Karyawan Test"},
    }


async def _setup_nomor_antrean(db: AsyncSession, toko) -> dict:
    perangkat = await buat_perangkat(db, toko.toko.id, toko.outlet.id, device_uid=f"device-{toko.toko.id}")
    return {
        "method": "POST", "url": "/antrean/nomor", "json": None,
        "params": {"outlet_id": str(toko.outlet.id), "perangkat_id": str(perangkat.id)},
    }


async def _setup_multi_outlet(db: AsyncSession, toko) -> dict:
    # toko fixture SUDAH punya 1 outlet - request ini mencoba outlet KE-2.
    return {"method": "POST", "url": "/outlets", "json": {"kode": "OUT2", "nama": "Outlet Kedua"}}


_SETUP: dict[str, _SetupFn] = {
    "resep": _setup_resep,
    "bundling": _setup_bundling,
    "harga_grosir": _setup_harga_grosir,
    "diskon": _setup_diskon,
    "tipe_order": _setup_tipe_order,
    "kelola_karyawan": _setup_kelola_karyawan,
    "nomor_antrean": _setup_nomor_antrean,
    "multi_outlet": _setup_multi_outlet,
}


@pytest.mark.parametrize("pemetaan", endpoint_tergate(), ids=lambda p: p.kode)
async def test_toko_gratis_ditolak_403_fitur_terkunci(
    client: AsyncClient, db_session: AsyncSession, pemetaan
) -> None:
    assert pemetaan.kode in _SETUP, (
        f"Baris fitur_map '{pemetaan.kode}' punya endpoint tapi belum ada setup tes - "
        "lengkapi _SETUP di tests/test_gating_fitur.py."
    )

    # multi_outlet butuh jumlah_outlet>=2 agar outlet ke-2 tidak kena
    # kuota (lihat outlet_service.py) - bukan soal fitur yg sedang dites.
    jumlah_outlet = 5 if pemetaan.kode == "multi_outlet" else 1
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Gratis", jumlah_outlet=jumlah_outlet)
    req = await _SETUP[pemetaan.kode](db_session, toko)

    resp = await client.request(
        req["method"], req["url"], headers=toko.headers, json=req.get("json"), params=req.get("params")
    )
    assert resp.status_code == 403, f"{pemetaan.kode}: expected 403, got {resp.status_code}: {resp.text}"
    detail = resp.json()["detail"]
    assert detail["kode"] == "fitur_terkunci"
    assert detail["fitur"] == pemetaan.kode
    assert detail["paket_minimal"] in ("Pro", "Bisnis")


@pytest.mark.parametrize("pemetaan", endpoint_tergate(), ids=lambda p: p.kode)
async def test_toko_bisnis_diterima(client: AsyncClient, db_session: AsyncSession, pemetaan) -> None:
    assert pemetaan.kode in _SETUP

    jumlah_outlet = 5 if pemetaan.kode == "multi_outlet" else 1
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis", jumlah_outlet=jumlah_outlet)
    req = await _SETUP[pemetaan.kode](db_session, toko)

    resp = await client.request(
        req["method"], req["url"], headers=toko.headers, json=req.get("json"), params=req.get("params")
    )
    assert resp.status_code not in (403, 404, 422), (
        f"{pemetaan.kode}: toko Bisnis seharusnya diterima, dapat {resp.status_code}: {resp.text}"
    )
    if resp.status_code == 403:
        assert resp.json().get("detail", {}).get("kode") != "fitur_terkunci"


async def test_toko_pro_tidak_dapat_fitur_tingkat_2(client: AsyncClient, db_session: AsyncSession) -> None:
    """Sanity check arah sebaliknya - toko Pro (tingkat 1) tetap ditolak
    utk fitur tingkat 2 (bundling)."""

    toko = await buat_toko_siap_pakai(db_session, nama_paket="Pro")
    req = await _setup_bundling(db_session, toko)
    resp = await client.request(req["method"], req["url"], headers=toko.headers, json=req["json"])
    assert resp.status_code == 403
    assert resp.json()["detail"]["paket_minimal"] == "Bisnis"


# ---------------------------------------------------------------------------
# Laporan - batas rentang hari per paket (B.4)
# ---------------------------------------------------------------------------


async def test_laporan_rentang_31_hari_ditolak_422_utk_paket_gratis(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    from datetime import UTC, datetime, timedelta

    toko = await buat_toko_siap_pakai(db_session, nama_paket="Gratis")
    sekarang = datetime.now(UTC)
    resp = await client.get(
        "/laporan/penjualan",
        headers=toko.headers,
        params={"dari": (sekarang - timedelta(days=31)).isoformat(), "sampai": sekarang.isoformat()},
    )
    assert resp.status_code == 422
    assert resp.json()["detail"]["kode"] == "rentang_laporan_melebihi_batas"
    assert resp.json()["detail"]["batas_hari"] == 30


async def test_laporan_rentang_29_hari_diterima_utk_paket_gratis(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    from datetime import UTC, datetime, timedelta

    toko = await buat_toko_siap_pakai(db_session, nama_paket="Gratis")
    sekarang = datetime.now(UTC)
    resp = await client.get(
        "/laporan/penjualan",
        headers=toko.headers,
        params={"dari": (sekarang - timedelta(days=29)).isoformat(), "sampai": sekarang.isoformat()},
    )
    assert resp.status_code == 200


async def test_laporan_rentang_400_hari_diterima_utk_paket_bisnis(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    from datetime import UTC, datetime, timedelta

    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    sekarang = datetime.now(UTC)
    resp = await client.get(
        "/laporan/penjualan",
        headers=toko.headers,
        params={"dari": (sekarang - timedelta(days=400)).isoformat(), "sampai": sekarang.isoformat()},
    )
    assert resp.status_code == 200


# ---------------------------------------------------------------------------
# Kuota outlet (B.5)
# ---------------------------------------------------------------------------


async def test_tambah_outlet_melebihi_kuota_langganan_ditolak(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    # Bisnis (fitur multi_outlet terbuka) tapi langganan cuma bayar 1 outlet.
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis", jumlah_outlet=1)
    resp = await client.post("/outlets", headers=toko.headers, json={"kode": "OUT2", "nama": "Outlet Kedua"})
    assert resp.status_code == 403
    assert resp.json()["detail"] == {"kode": "kuota_habis", "jenis": "outlet", "batas": 1}


async def test_tambah_outlet_dalam_kuota_diterima(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis", jumlah_outlet=2)
    resp = await client.post("/outlets", headers=toko.headers, json={"kode": "OUT2", "nama": "Outlet Kedua"})
    assert resp.status_code == 201


async def test_sync_pull_mengirim_batas_fitur(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Gratis")
    perangkat = await buat_perangkat(db_session, toko.toko.id, toko.outlet.id)
    resp = await client.get(
        "/sync/pull",
        headers=toko.headers,
        params={"perangkat_id": str(perangkat.id), "since": "1970-01-01T00:00:00Z"},
    )
    assert resp.status_code == 200
    assert resp.json()["batas_fitur"] == {"laporan_dasar": 30}


# ---------------------------------------------------------------------------
# Kuota pengguna (tahap 3a A.2) - kelola_karyawan TIDAK lagi menggating CRUD
# pengguna dasar, diganti kuota paket.maks_pengguna.
# ---------------------------------------------------------------------------


async def test_tambah_pengguna_gratis_tidak_lagi_butuh_fitur_kelola_karyawan(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Gratis")
    resp = await client.post(
        "/pengguna",
        headers=toko.headers,
        json={"role_id": str(toko.role.id), "nama": "Kasir Baru", "outlet_ids": []},
    )
    assert resp.status_code == 201


async def test_tambah_pengguna_melebihi_kuota_paket_ditolak(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    from sqlalchemy import select

    from app.models.outlet import Paket

    toko = await buat_toko_siap_pakai(db_session, nama_paket="Gratis")
    paket = (await db_session.execute(select(Paket).where(Paket.nama == "Gratis"))).scalar_one()
    paket.maks_pengguna = 1  # toko sudah punya 1 pengguna (Owner) dari setup
    await db_session.commit()

    resp = await client.post(
        "/pengguna",
        headers=toko.headers,
        json={"role_id": str(toko.role.id), "nama": "Kasir Baru", "outlet_ids": []},
    )
    assert resp.status_code == 403
    assert resp.json()["detail"] == {"kode": "kuota_habis", "jenis": "pengguna", "batas": 1}


# ---------------------------------------------------------------------------
# paket_efektif (tahap 3a A.3) - langganan kedaluwarsa turun ke Gratis,
# bukan "tanpa batas apa pun".
# ---------------------------------------------------------------------------


async def test_langganan_kedaluwarsa_turun_ke_gratis(client: AsyncClient, db_session: AsyncSession) -> None:
    from datetime import UTC, datetime, timedelta

    from sqlalchemy import select

    from app.models.outlet import Langganan

    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    langganan = (
        await db_session.execute(select(Langganan).where(Langganan.toko_id == toko.toko.id))
    ).scalar_one()
    langganan.berakhir = datetime.now(UTC) - timedelta(days=1)
    await db_session.commit()

    # Fitur Bisnis (mis. resep) sekarang harus terkunci lagi - BUKAN
    # error/500, data toko tidak dihapus, cuma fiturnya terkunci.
    produk = await buat_produk(db_session, toko.toko.id, nama="Nasi Goreng")
    resp = await client.post(
        f"/produk/{produk.id}/resep", headers=toko.headers, json={"bahan_id": str(produk.id), "qty": "1"}
    )
    assert resp.status_code == 403
    assert resp.json()["detail"]["kode"] == "fitur_terkunci"

    resp_fitur = await client.get("/fitur/toko", headers=toko.headers)
    assert resp_fitur.status_code == 200
    assert resp_fitur.json()["paket"] == "Gratis"


# ---------------------------------------------------------------------------
# Temuan#3 (rapikan F3) - kuota outlet/pengguna/produk WAJIB ikut turun ke
# kuota paket Gratis begitu langganan berbayar kedaluwarsa (data lama tetap
# ada, cuma tidak bisa menambah baru) - bukan diam2 tetap pakai kuota lama.
# ---------------------------------------------------------------------------


async def test_kuota_outlet_setelah_langganan_kedaluwarsa_turun_ke_gratis(
    db_session: AsyncSession,
) -> None:
    """Dites lewat service langsung (bukan HTTP POST /outlets) supaya tidak
    ketimpa duluan oleh gating fitur `multi_outlet` (toko yang turun ke
    Gratis otomatis juga kehilangan fitur itu, gate terpisah dari kuota
    ini) - fokus murni membuktikan jumlah_outlet dari langganan yang SUDAH
    kedaluwarsa tidak lagi dipakai (bug nyata yang diperbaiki di
    outlet_service.py: dulu query Langganan di sana cuma filter
    status='aktif', TIDAK cek `berakhir` seperti paket_efektif)."""
    from datetime import UTC, datetime, timedelta

    from fastapi import HTTPException
    from sqlalchemy import select

    from app.models.outlet import Langganan, Paket
    from app.services.outlet_service import pastikan_kuota_outlet

    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis", jumlah_outlet=5)
    gratis = (await db_session.execute(select(Paket).where(Paket.nama == "Gratis"))).scalar_one()
    gratis.maks_outlet = 1
    langganan = (
        await db_session.execute(select(Langganan).where(Langganan.toko_id == toko.toko.id))
    ).scalar_one()
    langganan.berakhir = datetime.now(UTC) - timedelta(days=1)
    await db_session.commit()

    # Toko sudah punya 1 outlet (OUT1 dari buat_toko_siap_pakai) - kuota
    # Gratis cuma 1, jadi outlet KE-2 harus ditolak walau langganan LAMA
    # (sudah kedaluwarsa) bilang jumlah_outlet=5.
    with pytest.raises(HTTPException) as exc:
        await pastikan_kuota_outlet(db_session, toko_id=toko.toko.id, jumlah_sekarang=1)
    assert exc.value.detail == {"kode": "kuota_habis", "jenis": "outlet", "batas": 1}


async def test_kuota_pengguna_setelah_langganan_kedaluwarsa_turun_ke_gratis(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    from datetime import UTC, datetime, timedelta

    from sqlalchemy import select

    from app.models.outlet import Langganan, Paket

    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    gratis = (await db_session.execute(select(Paket).where(Paket.nama == "Gratis"))).scalar_one()
    gratis.maks_pengguna = 1  # toko sudah punya 1 pengguna (Owner)
    langganan = (
        await db_session.execute(select(Langganan).where(Langganan.toko_id == toko.toko.id))
    ).scalar_one()
    langganan.berakhir = datetime.now(UTC) - timedelta(days=1)
    await db_session.commit()

    resp = await client.post(
        "/pengguna",
        headers=toko.headers,
        json={"role_id": str(toko.role.id), "nama": "Kasir Baru", "outlet_ids": []},
    )
    assert resp.status_code == 403
    assert resp.json()["detail"] == {"kode": "kuota_habis", "jenis": "pengguna", "batas": 1}


async def test_kuota_produk_ditegakkan_dan_turun_ke_gratis_setelah_kedaluwarsa(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    """Sekaligus bukti file:baris: sebelum temuan#3, POST /produk
    (app/routers/produk.py) TIDAK PERNAH mengecek paket.maks_produk sama
    sekali - endpoint-nya cuma _pastikan_kategori_satuan_milik_toko lalu
    langsung simpan, tidak ada cek kuota apa pun (lihat git blame baris
    ini sebelum temuan#3)."""
    from datetime import UTC, datetime, timedelta

    from sqlalchemy import select

    from app.models.outlet import Langganan, Paket

    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    gratis = (await db_session.execute(select(Paket).where(Paket.nama == "Gratis"))).scalar_one()
    gratis.maks_produk = 1
    await db_session.commit()

    produk_1 = await buat_produk(db_session, toko.toko.id, nama="Produk Lama")
    # Soft-delete TIDAK dihitung - toko ini SEHARUSNYA masih bisa tambah 1
    # produk baru walau total baris produk (termasuk yang terhapus) > 1.
    produk_1.deleted_at = datetime.now(UTC)
    produk_2 = await buat_produk(db_session, toko.toko.id, nama="Produk Dihapus")
    produk_2.deleted_at = datetime.now(UTC)
    await db_session.commit()

    # Masih dalam kuota Bisnis (maks_produk None - tanpa batas) - diterima.
    resp_dalam_kuota = await client.post(
        "/produk", headers=toko.headers, json={"nama": "Produk Aktif Pertama", "harga_jual": "10000"}
    )
    assert resp_dalam_kuota.status_code == 201, resp_dalam_kuota.text

    # Sekarang kedaluwarsa-kan langganan -> turun ke kuota Gratis (1 produk
    # AKTIF - sudah terpenuhi oleh "Produk Aktif Pertama" di atas, yang
    # soft-deleted TIDAK ikut dihitung).
    langganan = (
        await db_session.execute(select(Langganan).where(Langganan.toko_id == toko.toko.id))
    ).scalar_one()
    langganan.berakhir = datetime.now(UTC) - timedelta(days=1)
    await db_session.commit()

    resp_ditolak = await client.post(
        "/produk", headers=toko.headers, json={"nama": "Produk Kedua", "harga_jual": "10000"}
    )
    assert resp_ditolak.status_code == 403
    assert resp_ditolak.json()["detail"] == {"kode": "kuota_habis", "jenis": "produk", "batas": 1}
