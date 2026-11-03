"""Tes penyapu (sweep) - iterasi SEMUA route terdaftar di `app.routes`,
dan untuk tiap parameter path/query bertipe UUID (termasuk `UUID | None`),
panggil endpoint itu dengan token toko A tapi id milik toko B. Tujuannya
BUKAN menggantikan test_isolasi_toko.py (yang menguji skenario spesifik
lebih detail + efek sampingnya ke DB) - sweep ini murni pagar otomatis
supaya endpoint BARU yang lupa divalidasi kepemilikannya langsung
ketahuan tanpa perlu nulis tes manual lagi.

Aturan longgar tapi tegas: respons HARUS salah satu dari {403, 404, 422}.
422 diterima sbg hasil "aman" meski kadang itu krn body belum lengkap
(bukan krn pengecekan kepemilikan) - itu tetap longgar yg disengaja
(lihat instruksi tugas), yang PENTING tidak pernah 200/201 (artinya
endpoint diam-diam menerima/mengerjakan resource milik toko lain).

Body untuk endpoint POST/PATCH/PUT dibuat SELENGKAP MUNGKIN (bukan `{}`
asal lolos) supaya validasi Pydantic body tidak "menutupi" celah
kepemilikan yang seharusnya diuji - percuma sweep kalau semua kasus cuma
kena 422 krn body kosong, bukan krn kepemilikan benar2 dicek."""

import uuid
from datetime import UTC, date, datetime
from decimal import Decimal

import pytest
from fastapi.routing import APIRoute
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.main import app
from app.models.order import Meja, TipeOrder
from app.models.outlet import Outlet, Paket, PermintaanUpgrade
from app.models.pelanggan import LevelMember
from app.models.produk import (
    BundlingItem,
    GrupModifier,
    HargaGrosir,
    HargaOutlet,
    Kategori,
    Modifier,
    ProdukVarian,
    Resep,
)
from app.models.promo import Pajak, Promo
from tests.conftest import buat_metode_bayar, buat_perangkat, buat_produk, buat_toko_siap_pakai

# ---------------------------------------------------------------------------
# Pengecualian - route yang SENGAJA tidak disapu, dgn alasan.
# ---------------------------------------------------------------------------

# (method, path_template) yang dikecualikan SELURUHNYA.
ROUTE_DIKECUALIKAN: dict[tuple[str, str], str] = {
    ("PATCH", "/dapur/pesanan/{pesanan_id}/status"): (
        "Butuh setup kompleks (toko paket Bisnis + fitur tiket_dapur + "
        "stasiun_dapur + kategori tertaut + checkout sungguhan) hanya utk "
        "menghasilkan satu baris pesanan_dapur - kepemilikannya sekarang "
        "dites MANUAL di tests/test_order.py::test_ubah_status_pesanan_dapur_tolak_toko_lain "
        "(tahap 2, item A.4) - bukan dilewatkan begitu saja."
    ),
}

# (method, path_template, nama_param) utk mengecualikan SATU parameter
# saja di suatu route (route-nya tetap disapu utk parameter lain).
PARAM_DIKECUALIKAN: dict[tuple[str, str, str], str] = {
    ("GET", "/audit-log", "record_id"): (
        "record_id adalah referensi POLIMORFIK ke tabel mana pun "
        "(ditentukan oleh filter `tabel` yang terpisah) - tidak bisa "
        "divalidasi generik milik toko mana tanpa tahu tabel targetnya. "
        "Sudah aman via AND toko_id di query (record_id milik toko lain "
        "otomatis menghasilkan list kosong, bukan membocorkan 200 dengan "
        "data toko lain)."
    ),
}


# ---------------------------------------------------------------------------
# Setup data: satu dari setiap jenis entity, utk toko A dan toko B.
# ---------------------------------------------------------------------------


class _Konteks:
    def __init__(self) -> None:
        self.a: dict[str, uuid.UUID] = {}
        self.b: dict[str, uuid.UUID] = {}


async def _siapkan_satu_toko(client: AsyncClient, db: AsyncSession, toko, label: str) -> dict[str, uuid.UUID]:
    ids: dict[str, uuid.UUID] = {"outlet_id": toko.outlet.id, "pengguna_id": toko.pengguna.id}

    produk = await buat_produk(db, toko.toko.id, nama=f"Produk {label}")
    ids["produk_id"] = produk.id

    kategori = Kategori(toko_id=toko.toko.id, nama=f"Kategori {label}")
    db.add(kategori)
    await db.commit()
    ids["kategori_id"] = kategori.id

    grup = GrupModifier(toko_id=toko.toko.id, nama=f"Grup {label}")
    db.add(grup)
    await db.commit()
    ids["grup_modifier_id"] = grup.id

    modifier = Modifier(grup_modifier_id=grup.id, nama=f"Modifier {label}")
    db.add(modifier)
    await db.commit()
    ids["modifier_id"] = modifier.id

    varian = ProdukVarian(produk_id=produk.id, nama=f"Varian {label}")
    db.add(varian)
    await db.commit()
    ids["varian_id"] = varian.id

    resep = Resep(produk_id=produk.id, bahan_id=produk.id, qty=Decimal("1"))
    db.add(resep)
    await db.commit()
    ids["resep_id"] = resep.id

    produk_isi = await buat_produk(db, toko.toko.id, nama=f"Produk Isi {label}")
    bundling = BundlingItem(bundling_produk_id=produk.id, produk_id=produk_isi.id, qty=Decimal("1"))
    db.add(bundling)
    await db.commit()
    ids["bundling_id"] = bundling.id

    harga_grosir = HargaGrosir(produk_id=produk.id, min_qty=Decimal("5"), harga=Decimal("1000"))
    db.add(harga_grosir)
    await db.commit()
    ids["harga_grosir_id"] = harga_grosir.id

    harga_outlet = HargaOutlet(produk_id=produk.id, outlet_id=toko.outlet.id, harga_jual=Decimal("1000"))
    db.add(harga_outlet)
    await db.commit()
    ids["harga_outlet_id"] = harga_outlet.id

    pajak = Pajak(toko_id=toko.toko.id, nama=f"Pajak {label}", persen=Decimal("10"))
    db.add(pajak)
    await db.commit()
    ids["pajak_id"] = pajak.id

    promo = Promo(toko_id=toko.toko.id, nama=f"Promo {label}", tipe="nominal", nilai=Decimal("1000"))
    db.add(promo)
    await db.commit()
    ids["promo_id"] = promo.id

    level_member = LevelMember(toko_id=toko.toko.id, nama=f"Level {label}")
    db.add(level_member)
    await db.commit()
    ids["level_id"] = level_member.id

    tipe_order = TipeOrder(toko_id=toko.toko.id, nama=f"Tipe {label}")
    db.add(tipe_order)
    await db.commit()
    ids["tipe_order_id"] = tipe_order.id

    meja = Meja(outlet_id=toko.outlet.id, nama=f"Meja {label}")
    db.add(meja)
    await db.commit()
    ids["meja_id"] = meja.id

    pelanggan_resp = await client.post(
        "/pelanggan", headers=toko.headers, json={"nama": f"Pelanggan {label}"}
    )
    assert pelanggan_resp.status_code == 201
    ids["pelanggan_id"] = uuid.UUID(pelanggan_resp.json()["id"])

    metode = await buat_metode_bayar(db, toko.toko.id)
    ids["metode_bayar_id"] = metode.id
    perangkat = await buat_perangkat(db, toko.toko.id, toko.outlet.id, device_uid=f"device-sweep-{label}")
    ids["perangkat_id"] = perangkat.id

    shift_resp = await client.post(
        "/shift/buka", headers=toko.headers, json={"outlet_id": str(toko.outlet.id), "modal_awal": "0"}
    )
    assert shift_resp.status_code == 201
    ids["shift_id"] = uuid.UUID(shift_resp.json()["id"])

    transaksi_resp = await client.post(
        "/transaksi",
        headers=toko.headers,
        json={
            "outlet_id": str(toko.outlet.id),
            "nomor_struk": f"SWEEP-{label}-1",
            "tanggal": datetime.now(UTC).isoformat(),
            "items": [
                {"produk_id": str(produk.id), "nama_produk": produk.nama, "qty": "1", "harga_satuan": "15000"}
            ],
            "metode_bayar_id": str(metode.id),
            "total_bayar": "15000",
        },
    )
    assert transaksi_resp.status_code == 201
    ids["transaksi_id"] = uuid.UUID(transaksi_resp.json()["id"])

    pembelian_resp = await client.post(
        "/pembelian",
        headers=toko.headers,
        json={
            "outlet_id": str(toko.outlet.id),
            "nomor": f"SWEEP-PO-{label}",
            "tanggal": date.today().isoformat(),
            "items": [{"produk_id": str(produk.id), "qty": "1", "harga_satuan": "1000"}],
        },
    )
    assert pembelian_resp.status_code == 201
    ids["pembelian_id"] = uuid.UUID(pembelian_resp.json()["id"])

    opname_resp = await client.post(
        "/stok-opname",
        headers=toko.headers,
        json={
            "outlet_id": str(toko.outlet.id),
            "nomor": f"SWEEP-OPN-{label}",
            "tanggal": date.today().isoformat(),
            "items": [{"produk_id": str(produk.id), "qty_fisik": "1"}],
        },
    )
    assert opname_resp.status_code == 201
    ids["opname_id"] = uuid.UUID(opname_resp.json()["id"])

    pesanan_resp = await client.post(
        "/transaksi/pesanan-tersimpan",
        headers=toko.headers,
        json={
            "id": str(uuid.uuid4()),
            "outlet_id": str(toko.outlet.id),
            "nomor_struk": f"SWEEP-DRAFT-{label}",
            "tanggal": datetime.now(UTC).isoformat(),
            "items": [
                {"produk_id": str(produk.id), "nama_produk": produk.nama, "qty": "1", "harga_satuan": "15000"}
            ],
        },
    )
    assert pesanan_resp.status_code == 201
    ids["pesanan_id"] = uuid.UUID(pesanan_resp.json()["id"])

    outlet2 = Outlet(toko_id=toko.toko.id, kode=f"OUT2{label}", nama=f"Outlet 2 {label}")
    db.add(outlet2)
    await db.commit()
    transfer_resp = await client.post(
        "/transfer-stok",
        headers=toko.headers,
        json={
            "dari_outlet_id": str(toko.outlet.id),
            "ke_outlet_id": str(outlet2.id),
            "nomor": f"SWEEP-TRF-{label}",
            "items": [{"produk_id": str(produk.id), "qty": "1"}],
        },
    )
    assert transfer_resp.status_code == 201
    ids["transfer_id"] = uuid.UUID(transfer_resp.json()["id"])

    paket_apa_saja = (await db.execute(select(Paket).limit(1))).scalars().first()
    permintaan = PermintaanUpgrade(
        toko_id=toko.toko.id, paket_tujuan_id=paket_apa_saja.id, jumlah_bayar=Decimal("1000")
    )
    db.add(permintaan)
    await db.commit()
    ids["permintaan_id"] = permintaan.id

    return ids


@pytest.fixture
async def konteks(client: AsyncClient, db_session: AsyncSession) -> _Konteks:
    # Tahap 5 - sweep sekarang ikut membuat baris promo/tipe-order/resep/
    # bundling/harga-grosir/level-member/aturan-poin (semua fitur
    # berbayar) - pakai toko paket "Bisnis" sendiri (BUKAN toko_a/toko_b
    # dari conftest yang defaultnya "Gratis" dan dipakai tes lain yang
    # SENGAJA butuh Gratis) supaya setup ini tidak ditolak 403 fitur_terkunci.
    toko_a = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    toko_b = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    ctx = _Konteks()
    ctx.a = await _siapkan_satu_toko(client, db_session, toko_a, "A")
    ctx.b = await _siapkan_satu_toko(client, db_session, toko_b, "B")
    return ctx


# ---------------------------------------------------------------------------
# Body minimal-tapi-lengkap per (method, path_template) - supaya 422 yang
# muncul (kalau ada) bukan krn body kosong, tapi beneran krn kepemilikan.
# `None` = tidak perlu body (GET/DELETE, atau POST tanpa JSON body).
# ---------------------------------------------------------------------------


def _body_untuk(method: str, path: str, ids: dict[str, uuid.UUID]) -> dict | None:
    if method in ("GET", "DELETE"):
        return None

    if path == "/outlets/{outlet_id}":
        return {}  # OutletUpdateIn - semua field opsional
    if path == "/outlets/{outlet_id}/pengaturan":
        return {}  # PengaturanOutletIn - semua field opsional
    if path == "/metode-bayar/{metode_bayar_id}":
        return {}  # MetodeBayarUpdateIn - semua field opsional
    if path == "/produk/{produk_id}":
        return {}  # ProdukUpdateIn - semua field opsional
    if path == "/produk/{produk_id}/varian":
        return {"nama": "Varian Sweep"}
    if path == "/grup-modifier/{grup_modifier_id}/modifier":
        return {"nama": "Modifier Sweep"}
    if path == "/produk/{produk_id}/grup-modifier/{grup_modifier_id}":
        return None  # PUT tanpa body JSON
    if path == "/produk/{produk_id}/resep":
        return {"bahan_id": str(ids["produk_id"]), "qty": "1"}
    if path == "/produk/{produk_id}/bundling":
        return {"produk_id": str(ids["produk_id"]), "qty": "1"}
    if path == "/produk/{produk_id}/harga-grosir":
        return {"min_qty": "1", "harga": "1000"}
    if path == "/produk/{produk_id}/harga-outlet":
        return {"outlet_id": str(ids["outlet_id"]), "harga_jual": "1000"}
    if path == "/pengguna/{pengguna_id}":
        return {}  # PenggunaUpdateIn - semua field opsional
    if path == "/shift/{shift_id}/tutup":
        return {"kas_aktual": "0"}
    if path == "/shift/{shift_id}/kas":
        return {"jenis": "masuk", "jumlah": "1000", "keterangan": "sweep"}
    if path == "/transaksi/{transaksi_id}/void":
        return {"alasan": "sweep"}
    if path == "/transaksi/{transaksi_id}/refund":
        return {"alasan": "sweep", "items": []}
    if path == "/transaksi/pesanan-tersimpan/{pesanan_id}/batalkan":
        return {"alasan": "sweep"}
    if path == "/transaksi/{transaksi_id}/pembayaran":
        return {
            "shift_id": str(ids["shift_id"]),
            "metode_bayar_id": str(ids["metode_bayar_id"]),
            "jumlah": "1000",
        }
    if path == "/outlets/{outlet_id}/meja":
        return {"nama": "Meja Sweep"}
    if path == "/outlets/{outlet_id}/stasiun-dapur":
        return {"nama": "Stasiun Sweep"}
    if path in ("/antrean/nomor", "/pembelian/{pembelian_id}/terima", "/stok-opname/{opname_id}/selesai",
                "/transfer-stok/{transfer_id}/kirim", "/transfer-stok/{transfer_id}/terima",
                "/langganan/checkout-upgrade/{permintaan_id}/simulasi"):
        return None  # tidak perlu body JSON (query-only atau tanpa body)

    # Tahap 5 - endpoint PATCH/DELETE/link baru.
    if path in (
        "/pelanggan/{pelanggan_id}",
        "/level-member/{level_id}",
        "/aturan-poin",
        "/pajak/{pajak_id}",
        "/promo/{promo_id}",
        "/produk/{produk_id}/varian/{varian_id}",
        "/grup-modifier/{grup_modifier_id}",
        "/grup-modifier/{grup_modifier_id}/modifier/{modifier_id}",
        "/produk/{produk_id}/resep/{resep_id}",
        "/produk/{produk_id}/bundling/{bundling_id}",
        "/produk/{produk_id}/harga-grosir/{harga_grosir_id}",
        "/produk/{produk_id}/harga-outlet/{harga_outlet_id}",
        "/tipe-order/{tipe_order_id}",
        "/outlets/{outlet_id}/meja/{meja_id}",
        "/kategori/{kategori_id}",
    ):
        return {}  # semua *UpdateIn - field opsional
    if path == "/level-member":
        return {"nama": "Level Sweep"}
    if path in ("/promo/{promo_id}/produk", "/promo/{promo_id}/outlet"):
        return {"ids": []}
    if path in (
        "/produk/{produk_id}/pajak/{pajak_id}",
        "/tipe-order/{tipe_order_id}/pajak/{pajak_id}",
    ):
        return None  # link idempoten, tanpa body JSON
    if path == "/pengguna/{pengguna_id}/reset-pin":
        return {"pin": "999999"}

    raise AssertionError(f"Body utk {method} {path} belum didefinisikan - lengkapi _body_untuk()")


def _query_dasar_untuk(path: str) -> dict:
    """Query param WAJIB yang bukan UUID (tanggal dkk) - diisi nilai aman
    supaya tidak 422 krn alasan yang tidak relevan dgn tes ini."""

    if path in ("/laporan/penjualan", "/laporan/produk-terlaris"):
        return {"dari": "2020-01-01T00:00:00Z", "sampai": "2030-01-01T00:00:00Z"}
    if path == "/sync/pull":
        return {"since": "1970-01-01T00:00:00Z"}
    return {}


def _is_uuid_type(type_: object) -> bool:
    if type_ is uuid.UUID:
        return True
    args = getattr(type_, "__args__", ())
    return uuid.UUID in args


def _kumpulkan_target() -> list[tuple[str, str, str, str]]:
    """Return list of (method, path_template, param_name, lokasi) utk
    setiap parameter UUID path/query di seluruh app.routes - `lokasi` is
    "path" atau "query"."""

    target: list[tuple[str, str, str, str]] = []
    for route in app.routes:
        if not isinstance(route, APIRoute):
            continue
        for method in sorted(route.methods - {"HEAD", "OPTIONS"}):
            for p in route.dependant.path_params:
                if _is_uuid_type(p.type_):
                    target.append((method, route.path, p.name, "path"))
            for p in route.dependant.query_params:
                if _is_uuid_type(p.type_):
                    target.append((method, route.path, p.name, "query"))
    return target


async def test_semua_endpoint_tolak_id_milik_toko_lain(
    client: AsyncClient, konteks: _Konteks, toko_a
) -> None:
    semua_target = _kumpulkan_target()
    assert semua_target, "Tidak ada target UUID ditemukan - kemungkinan introspeksi route rusak"

    # Semua nama param UUID yang ditemukan di route HARUS ada di konteks A/B
    # (kalau ada nama baru yang tidak dikenal, gagalkan tes ini dgn jelas
    # drpd diam-diam skip - itu persis skenario "endpoint baru lupa
    # didaftarkan" yang sweep ini harus tangkap).
    dikenal = set(konteks.a.keys())

    kegagalan: list[str] = []
    diuji = 0

    for method, path_template, param_name, lokasi in semua_target:
        if (method, path_template) in ROUTE_DIKECUALIKAN:
            continue
        if (method, path_template, param_name) in PARAM_DIKECUALIKAN:
            continue
        if param_name not in dikenal:
            kegagalan.append(
                f"{method} {path_template}: parameter '{param_name}' ({lokasi}) tidak dikenal oleh "
                "sweep - tambahkan ke _siapkan_satu_toko() atau ke daftar pengecualian dgn alasan."
            )
            continue

        # Bangun path params: semua pakai id toko A yang valid, KECUALI
        # param_name yang diuji sekarang -> diganti id toko B.
        path_kwargs: dict[str, str] = {}
        route_path_names = [
            n for (m, pt, n, lk) in semua_target if m == method and pt == path_template and lk == "path"
        ]
        for name in set(route_path_names):
            path_kwargs[name] = str(konteks.b[name] if (name == param_name and lokasi == "path") else konteks.a[name])

        url = path_template.format(**path_kwargs)

        query: dict[str, str] = dict(_query_dasar_untuk(path_template))
        route_query_names = [
            n for (m, pt, n, lk) in semua_target if m == method and pt == path_template and lk == "query"
        ]
        for name in set(route_query_names):
            query[name] = str(konteks.b[name] if (name == param_name and lokasi == "query") else konteks.a[name])

        body = _body_untuk(method, path_template, konteks.a)

        diuji += 1
        resp = await client.request(method, url, headers=toko_a.headers, params=query or None, json=body)

        if resp.status_code not in (403, 404, 422):
            kegagalan.append(
                f"{method} {path_template} (param '{param_name}' [{lokasi}] diganti milik toko B) -> "
                f"HTTP {resp.status_code} (SEHARUSNYA 403/404/422). Body response: {resp.text[:300]}"
            )

    assert diuji > 0, "Tidak ada kombinasi route+param yang benar2 diuji - cek logika sweep"
    assert not kegagalan, "Ditemukan endpoint yang menerima id milik toko lain:\n" + "\n".join(kegagalan)
