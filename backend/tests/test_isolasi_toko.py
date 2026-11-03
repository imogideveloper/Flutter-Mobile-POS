"""Tes isolasi multi-tenant - lihat audit sebelumnya: beberapa service
menerima outlet_id/produk_id/shift_id/supplier_id dari body klien tanpa
memvalidasi kepemilikan toko, memungkinkan toko A merusak/mencuri stok &
kas toko B lewat API resmi. Tes ini memastikan token toko A yang memakai
resource milik toko B selalu ditolak 404 (generik, tidak membocorkan bahwa
datanya ada di toko lain) DAN data toko B benar-benar tidak berubah."""

import uuid
from datetime import UTC, datetime
from decimal import Decimal

from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.akun import Pengguna, Role
from app.models.outlet import Outlet
from app.models.produk import Produk, ProdukVarian
from app.models.stok import MutasiStok, Pembelian, Stok, StokOpname, Supplier, TransferStok
from app.models.transaksi import Shift
from tests.conftest import buat_metode_bayar, buat_perangkat, buat_produk, buat_toko_siap_pakai


async def _buka_shift(client: AsyncClient, toko, *, modal_awal: str = "100000") -> str:
    resp = await client.post(
        "/shift/buka",
        headers=toko.headers,
        json={"outlet_id": str(toko.outlet.id), "modal_awal": modal_awal},
    )
    assert resp.status_code == 201
    return resp.json()["id"]


def _checkout_body(
    *, outlet_id, produk_id, metode_bayar_id, nomor_struk="OUT1-X1", shift_id=None, pelanggan_id=None,
    tipe_order_id=None, meja_id=None, harga="15000",
) -> dict:
    return {
        "outlet_id": str(outlet_id),
        "shift_id": str(shift_id) if shift_id else None,
        "pelanggan_id": str(pelanggan_id) if pelanggan_id else None,
        "tipe_order_id": str(tipe_order_id) if tipe_order_id else None,
        "meja_id": str(meja_id) if meja_id else None,
        "nomor_struk": nomor_struk,
        "tanggal": datetime.now(UTC).isoformat(),
        "items": [
            {"produk_id": str(produk_id), "nama_produk": "Produk", "qty": "1", "harga_satuan": harga}
        ],
        "metode_bayar_id": str(metode_bayar_id),
        "total_bayar": harga,
    }


# ---------------------------------------------------------------------------
# Checkout (POST /transaksi)
# ---------------------------------------------------------------------------


async def test_checkout_tolak_outlet_milik_toko_lain(
    client: AsyncClient, db_session: AsyncSession, toko_a, toko_b
) -> None:
    produk_b = await buat_produk(db_session, toko_b.toko.id)
    metode_b = await buat_metode_bayar(db_session, toko_b.toko.id)

    resp = await client.post(
        "/transaksi",
        headers=toko_a.headers,
        json=_checkout_body(outlet_id=toko_b.outlet.id, produk_id=produk_b.id, metode_bayar_id=metode_b.id),
    )
    assert resp.status_code == 404

    stok_b = (await db_session.execute(select(Stok).where(Stok.outlet_id == toko_b.outlet.id))).scalars().all()
    assert stok_b == []


async def test_checkout_tolak_produk_milik_toko_lain(
    client: AsyncClient, db_session: AsyncSession, toko_a, toko_b
) -> None:
    produk_b = await buat_produk(db_session, toko_b.toko.id)
    metode_a = await buat_metode_bayar(db_session, toko_a.toko.id)

    resp = await client.post(
        "/transaksi",
        headers=toko_a.headers,
        json=_checkout_body(outlet_id=toko_a.outlet.id, produk_id=produk_b.id, metode_bayar_id=metode_a.id),
    )
    assert resp.status_code == 404

    mutasi_b = (
        await db_session.execute(select(MutasiStok).where(MutasiStok.toko_id == toko_b.toko.id))
    ).scalars().all()
    assert mutasi_b == []


async def test_checkout_tolak_metode_bayar_milik_toko_lain(
    client: AsyncClient, db_session: AsyncSession, toko_a, toko_b
) -> None:
    produk_a = await buat_produk(db_session, toko_a.toko.id)
    metode_b = await buat_metode_bayar(db_session, toko_b.toko.id)

    resp = await client.post(
        "/transaksi",
        headers=toko_a.headers,
        json=_checkout_body(outlet_id=toko_a.outlet.id, produk_id=produk_a.id, metode_bayar_id=metode_b.id),
    )
    assert resp.status_code == 404


async def test_checkout_tolak_shift_milik_toko_lain(
    client: AsyncClient, db_session: AsyncSession, toko_a, toko_b
) -> None:
    produk_a = await buat_produk(db_session, toko_a.toko.id)
    metode_a = await buat_metode_bayar(db_session, toko_a.toko.id)
    shift_b_id = await _buka_shift(client, toko_b)

    resp = await client.post(
        "/transaksi",
        headers=toko_a.headers,
        json=_checkout_body(
            outlet_id=toko_a.outlet.id, produk_id=produk_a.id, metode_bayar_id=metode_a.id, shift_id=shift_b_id
        ),
    )
    assert resp.status_code == 404

    shift_b = await db_session.get(Shift, uuid.UUID(shift_b_id))
    assert shift_b.status == "buka"  # tidak tersentuh sama sekali


async def test_checkout_tolak_pelanggan_milik_toko_lain(
    client: AsyncClient, db_session: AsyncSession, toko_a, toko_b
) -> None:
    from app.models.pelanggan import Pelanggan

    produk_a = await buat_produk(db_session, toko_a.toko.id)
    metode_a = await buat_metode_bayar(db_session, toko_a.toko.id)
    pelanggan_b = Pelanggan(toko_id=toko_b.toko.id, nama="Pelanggan B")
    db_session.add(pelanggan_b)
    await db_session.commit()

    resp = await client.post(
        "/transaksi",
        headers=toko_a.headers,
        json=_checkout_body(
            outlet_id=toko_a.outlet.id, produk_id=produk_a.id, metode_bayar_id=metode_a.id,
            pelanggan_id=pelanggan_b.id,
        ),
    )
    assert resp.status_code == 404


# ---------------------------------------------------------------------------
# Transfer stok (POST /transfer-stok)
# ---------------------------------------------------------------------------


async def test_transfer_stok_tolak_outlet_asal_milik_toko_lain(
    client: AsyncClient, db_session: AsyncSession, toko_a, toko_b
) -> None:
    produk_a = await buat_produk(db_session, toko_a.toko.id)

    resp = await client.post(
        "/transfer-stok",
        headers=toko_a.headers,
        json={
            "dari_outlet_id": str(toko_b.outlet.id),
            "ke_outlet_id": str(toko_a.outlet.id),
            "nomor": "TRF-1",
            "items": [{"produk_id": str(produk_a.id), "qty": "5"}],
        },
    )
    assert resp.status_code == 404

    transfer_b = (
        await db_session.execute(select(TransferStok).where(TransferStok.toko_id == toko_b.toko.id))
    ).scalars().all()
    assert transfer_b == []
    mutasi_b = (
        await db_session.execute(select(MutasiStok).where(MutasiStok.outlet_id == toko_b.outlet.id))
    ).scalars().all()
    assert mutasi_b == []


async def test_transfer_stok_tolak_outlet_tujuan_milik_toko_lain(
    client: AsyncClient, db_session: AsyncSession, toko_a, toko_b
) -> None:
    produk_a = await buat_produk(db_session, toko_a.toko.id)

    resp = await client.post(
        "/transfer-stok",
        headers=toko_a.headers,
        json={
            "dari_outlet_id": str(toko_a.outlet.id),
            "ke_outlet_id": str(toko_b.outlet.id),
            "nomor": "TRF-2",
            "items": [{"produk_id": str(produk_a.id), "qty": "5"}],
        },
    )
    assert resp.status_code == 404


async def test_transfer_stok_tolak_produk_milik_toko_lain(
    client: AsyncClient, db_session: AsyncSession, toko_a, toko_b
) -> None:
    outlet_a2 = Outlet(toko_id=toko_a.toko.id, kode="OUT2", nama="Outlet Kedua A")
    db_session.add(outlet_a2)
    await db_session.commit()
    produk_b = await buat_produk(db_session, toko_b.toko.id)

    resp = await client.post(
        "/transfer-stok",
        headers=toko_a.headers,
        json={
            "dari_outlet_id": str(toko_a.outlet.id),
            "ke_outlet_id": str(outlet_a2.id),
            "nomor": "TRF-3",
            "items": [{"produk_id": str(produk_b.id), "qty": "5"}],
        },
    )
    assert resp.status_code == 404


# ---------------------------------------------------------------------------
# Pembelian (POST /pembelian)
# ---------------------------------------------------------------------------


async def test_pembelian_tolak_outlet_milik_toko_lain(
    client: AsyncClient, db_session: AsyncSession, toko_a, toko_b
) -> None:
    produk_a = await buat_produk(db_session, toko_a.toko.id)

    resp = await client.post(
        "/pembelian",
        headers=toko_a.headers,
        json={
            "outlet_id": str(toko_b.outlet.id),
            "nomor": "PO-1",
            "tanggal": datetime.now(UTC).date().isoformat(),
            "items": [{"produk_id": str(produk_a.id), "qty": "10", "harga_satuan": "1000"}],
        },
    )
    assert resp.status_code == 404

    pembelian_b = (
        await db_session.execute(select(Pembelian).where(Pembelian.toko_id == toko_b.toko.id))
    ).scalars().all()
    assert pembelian_b == []


async def test_pembelian_tolak_supplier_milik_toko_lain(
    client: AsyncClient, db_session: AsyncSession, toko_a, toko_b
) -> None:
    produk_a = await buat_produk(db_session, toko_a.toko.id)
    supplier_b = Supplier(toko_id=toko_b.toko.id, nama="Supplier B")
    db_session.add(supplier_b)
    await db_session.commit()

    resp = await client.post(
        "/pembelian",
        headers=toko_a.headers,
        json={
            "outlet_id": str(toko_a.outlet.id),
            "supplier_id": str(supplier_b.id),
            "nomor": "PO-2",
            "tanggal": datetime.now(UTC).date().isoformat(),
            "items": [{"produk_id": str(produk_a.id), "qty": "10", "harga_satuan": "1000"}],
        },
    )
    assert resp.status_code == 404


async def test_pembelian_tolak_produk_milik_toko_lain(
    client: AsyncClient, db_session: AsyncSession, toko_a, toko_b
) -> None:
    produk_b = await buat_produk(db_session, toko_b.toko.id)

    resp = await client.post(
        "/pembelian",
        headers=toko_a.headers,
        json={
            "outlet_id": str(toko_a.outlet.id),
            "nomor": "PO-3",
            "tanggal": datetime.now(UTC).date().isoformat(),
            "items": [{"produk_id": str(produk_b.id), "qty": "10", "harga_satuan": "1000"}],
        },
    )
    assert resp.status_code == 404

    produk_b_fresh = await db_session.get(Produk, produk_b.id)
    assert produk_b_fresh.hpp == Decimal("0")  # HPP toko B tidak diubah oleh toko A


# ---------------------------------------------------------------------------
# Buka shift (POST /shift/buka)
# ---------------------------------------------------------------------------


async def test_buka_shift_tolak_outlet_milik_toko_lain(
    client: AsyncClient, db_session: AsyncSession, toko_a, toko_b
) -> None:
    resp = await client.post(
        "/shift/buka", headers=toko_a.headers, json={"outlet_id": str(toko_b.outlet.id), "modal_awal": "0"}
    )
    assert resp.status_code == 404

    shift_b = (
        await db_session.execute(select(Shift).where(Shift.outlet_id == toko_b.outlet.id))
    ).scalars().all()
    assert shift_b == []


# ---------------------------------------------------------------------------
# Sync push (POST /sync/push)
# ---------------------------------------------------------------------------


async def test_sync_push_shift_tolak_outlet_milik_toko_lain(
    client: AsyncClient, db_session: AsyncSession, toko_a, toko_b
) -> None:
    perangkat_a = await buat_perangkat(db_session, toko_a.toko.id, toko_a.outlet.id)
    shift_id = str(uuid.uuid4())

    resp = await client.post(
        "/sync/push",
        headers=toko_a.headers,
        json={
            "perangkat_id": str(perangkat_a.id),
            "shift": [
                {
                    "id": shift_id,
                    "outlet_id": str(toko_b.outlet.id),
                    "dibuka_pada": datetime.now(UTC).isoformat(),
                    "modal_awal": "0",
                    "status": "buka",
                }
            ],
        },
    )
    assert resp.status_code == 200
    hasil = resp.json()["shift"][0]
    assert hasil["status"] == "ditolak"

    shift_row = await db_session.get(Shift, uuid.UUID(shift_id))
    assert shift_row is None


async def test_sync_push_shift_tutup_tidak_terbuka_lagi_oleh_push_lama(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    perangkat = await buat_perangkat(db_session, toko_a.toko.id, toko_a.outlet.id)
    shift_id = str(uuid.uuid4())
    dibuka_pada = datetime.now(UTC)

    # 1) Push pertama: shift masih 'buka'.
    resp1 = await client.post(
        "/sync/push",
        headers=toko_a.headers,
        json={
            "perangkat_id": str(perangkat.id),
            "shift": [
                {
                    "id": shift_id, "outlet_id": str(toko_a.outlet.id), "dibuka_pada": dibuka_pada.isoformat(),
                    "modal_awal": "100000", "status": "buka",
                }
            ],
        },
    )
    assert resp1.json()["shift"][0]["status"] == "diterima"

    # 2) Push kedua: shift yang SAMA, sekarang 'tutup' dgn kas_aktual nyata.
    resp2 = await client.post(
        "/sync/push",
        headers=toko_a.headers,
        json={
            "perangkat_id": str(perangkat.id),
            "shift": [
                {
                    "id": shift_id, "outlet_id": str(toko_a.outlet.id), "dibuka_pada": dibuka_pada.isoformat(),
                    "ditutup_pada": datetime.now(UTC).isoformat(), "modal_awal": "100000",
                    "kas_aktual": "100000", "status": "tutup",
                }
            ],
        },
    )
    assert resp2.json()["shift"][0]["status"] == "diterima"

    shift_setelah_tutup = await db_session.get(Shift, uuid.UUID(shift_id))
    assert shift_setelah_tutup.status == "tutup"
    assert shift_setelah_tutup.kas_seharusnya == Decimal("100000")  # dihitung server, bukan dari HP

    # 3) Push KETIGA: retry lama dari device, masih berisi payload 'buka'
    #    (device belum tahu push ke-2 sukses) - HARUS diabaikan, bukan
    #    membalik status shift yang sudah tutup.
    resp3 = await client.post(
        "/sync/push",
        headers=toko_a.headers,
        json={
            "perangkat_id": str(perangkat.id),
            "shift": [
                {
                    "id": shift_id, "outlet_id": str(toko_a.outlet.id), "dibuka_pada": dibuka_pada.isoformat(),
                    "modal_awal": "100000", "status": "buka",
                }
            ],
        },
    )
    assert resp3.status_code == 200
    assert resp3.json()["shift"][0]["status"] == "sudah_ada"

    shift_akhir = await db_session.get(Shift, uuid.UUID(shift_id))
    assert shift_akhir.status == "tutup"
    assert shift_akhir.kas_aktual == Decimal("100000")
    assert shift_akhir.kas_seharusnya == Decimal("100000")


async def test_sync_push_kas_seharusnya_dihitung_ulang_server_bukan_dari_hp(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    perangkat = await buat_perangkat(db_session, toko_a.toko.id, toko_a.outlet.id)
    shift_id = str(uuid.uuid4())

    resp = await client.post(
        "/sync/push",
        headers=toko_a.headers,
        json={
            "perangkat_id": str(perangkat.id),
            "shift": [
                {
                    "id": shift_id, "outlet_id": str(toko_a.outlet.id),
                    "dibuka_pada": datetime.now(UTC).isoformat(),
                    "ditutup_pada": datetime.now(UTC).isoformat(),
                    "modal_awal": "50000",
                    # Nilai bohong dari HP - tidak ada transaksi/kas_shift
                    # sama sekali utk shift ini, jadi kas_seharusnya yg
                    # BENAR adalah persis modal_awal (50000), bukan ini.
                    "kas_seharusnya": "999999999",
                    "kas_aktual": "50000",
                    "selisih": "0",
                    "status": "tutup",
                }
            ],
        },
    )
    assert resp.json()["shift"][0]["status"] == "diterima"

    shift_row = await db_session.get(Shift, uuid.UUID(shift_id))
    assert shift_row.kas_seharusnya == Decimal("50000")
    assert shift_row.selisih == Decimal("0")


async def test_sync_push_transaksi_bentrok_tidak_bikin_batch_500(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    """Dua item transaksi dgn id BEDA tapi nomor_struk+outlet sama (unique
    constraint DB) - mensimulasikan push bersamaan yg bentrok di level DB.
    Item pertama harus sukses, item kedua ditolak rapi (bukan 500 yg
    menggagalkan seluruh batch)."""

    produk = await buat_produk(db_session, toko_a.toko.id)
    metode = await buat_metode_bayar(db_session, toko_a.toko.id)
    perangkat = await buat_perangkat(db_session, toko_a.toko.id, toko_a.outlet.id)

    item1 = _checkout_body(
        outlet_id=toko_a.outlet.id, produk_id=produk.id, metode_bayar_id=metode.id, nomor_struk="DUP-1"
    )
    item1["id"] = str(uuid.uuid4())
    item2 = _checkout_body(
        outlet_id=toko_a.outlet.id, produk_id=produk.id, metode_bayar_id=metode.id, nomor_struk="DUP-1"
    )
    item2["id"] = str(uuid.uuid4())

    resp = await client.post(
        "/sync/push",
        headers=toko_a.headers,
        json={"perangkat_id": str(perangkat.id), "transaksi": [item1, item2]},
    )
    assert resp.status_code == 200  # BUKAN 500

    hasil = resp.json()["transaksi"]
    statuses = sorted(h["status"] for h in hasil)
    assert statuses == ["diterima", "ditolak"]


# ---------------------------------------------------------------------------
# Pengguna - wajib izin pengguna.kelola
# ---------------------------------------------------------------------------


async def test_pengguna_post_oleh_kasir_ditolak_403(client: AsyncClient, db_session: AsyncSession) -> None:
    kasir_toko = await buat_toko_siap_pakai(db_session, nama_role="Kasir")

    resp = await client.post(
        "/pengguna",
        headers=kasir_toko.headers,
        json={"role_id": str(kasir_toko.role.id), "nama": "Karyawan Baru"},
    )
    assert resp.status_code == 403

    pengguna_baru = (
        await db_session.execute(
            select(Pengguna).where(Pengguna.toko_id == kasir_toko.toko.id, Pengguna.nama == "Karyawan Baru")
        )
    ).scalars().all()
    assert pengguna_baru == []


async def test_pengguna_patch_oleh_kasir_ditolak_403(client: AsyncClient, db_session: AsyncSession) -> None:
    kasir_toko = await buat_toko_siap_pakai(db_session, nama_role="Kasir")

    resp = await client.patch(
        f"/pengguna/{kasir_toko.pengguna.id}", headers=kasir_toko.headers, json={"nama": "Nama Diubah"}
    )
    assert resp.status_code == 403

    pengguna = await db_session.get(Pengguna, kasir_toko.pengguna.id)
    assert pengguna.nama != "Nama Diubah"


async def test_pengguna_post_oleh_owner_tetap_boleh(client: AsyncClient, db_session: AsyncSession) -> None:
    """Pastikan perbaikan izin TIDAK ikut menolak Owner (yang memang punya
    izin pengguna.kelola) - regresi guard. Pakai toko Bisnis (bukan
    toko_a/toko_b default Gratis) krn kelola_karyawan kini fitur tingkat 1
    (lihat tests/test_gating_fitur.py utk tes gating-nya sendiri)."""

    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    resp = await client.post(
        "/pengguna", headers=toko.headers, json={"role_id": str(toko.role.id), "nama": "Karyawan Owner"}
    )
    assert resp.status_code == 201


async def test_pengguna_post_tolak_outlet_id_milik_toko_lain(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    toko_a = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    toko_b = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")

    resp = await client.post(
        "/pengguna",
        headers=toko_a.headers,
        json={"role_id": str(toko_a.role.id), "nama": "Karyawan X", "outlet_ids": [str(toko_b.outlet.id)]},
    )
    assert resp.status_code == 404

    pengguna_baru = (
        await db_session.execute(
            select(Pengguna).where(Pengguna.toko_id == toko_a.toko.id, Pengguna.nama == "Karyawan X")
        )
    ).scalars().all()
    assert pengguna_baru == []  # gagal total, bukan setengah jalan (pengguna dibuat tanpa AksesOutlet)


async def test_pengguna_patch_tolak_role_id_milik_toko_lain(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    toko_a = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    toko_b = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    role_custom_b = Role(toko_id=toko_b.toko.id, nama="Role Khusus B", is_system=False)
    db_session.add(role_custom_b)
    await db_session.commit()

    resp = await client.patch(
        f"/pengguna/{toko_a.pengguna.id}", headers=toko_a.headers, json={"role_id": str(role_custom_b.id)}
    )
    assert resp.status_code == 404

    pengguna = await db_session.get(Pengguna, toko_a.pengguna.id)
    assert pengguna.role_id != role_custom_b.id


# ---------------------------------------------------------------------------
# Sync pull (GET /sync/pull) - item 1
# ---------------------------------------------------------------------------


async def test_sync_pull_tolak_outlet_id_milik_toko_lain(
    client: AsyncClient, db_session: AsyncSession, toko_a, toko_b
) -> None:
    perangkat_a = await buat_perangkat(db_session, toko_a.toko.id, toko_a.outlet.id)

    resp = await client.get(
        "/sync/pull",
        headers=toko_a.headers,
        params={
            "perangkat_id": str(perangkat_a.id),
            "since": "1970-01-01T00:00:00Z",
            "outlet_id": str(toko_b.outlet.id),
        },
    )
    assert resp.status_code == 404


# ---------------------------------------------------------------------------
# Stok opname (POST /stok-opname) - item 2
# ---------------------------------------------------------------------------


async def test_stok_opname_tolak_produk_milik_toko_lain(
    client: AsyncClient, db_session: AsyncSession, toko_a, toko_b
) -> None:
    produk_b = await buat_produk(db_session, toko_b.toko.id)

    resp = await client.post(
        "/stok-opname",
        headers=toko_a.headers,
        json={
            "outlet_id": str(toko_a.outlet.id),
            "nomor": "OPN-1",
            "tanggal": datetime.now(UTC).date().isoformat(),
            "items": [{"produk_id": str(produk_b.id), "qty_fisik": "5"}],
        },
    )
    assert resp.status_code == 404

    opname_rows = (
        await db_session.execute(select(StokOpname).where(StokOpname.outlet_id == toko_a.outlet.id))
    ).scalars().all()
    assert opname_rows == []


# ---------------------------------------------------------------------------
# Produk lanjutan (varian/resep/bundling/harga_grosir/harga_outlet) - item 3
# ---------------------------------------------------------------------------


async def test_produk_tolak_kategori_milik_toko_lain(
    client: AsyncClient, db_session: AsyncSession, toko_a, toko_b
) -> None:
    from app.models.produk import Kategori

    kategori_b = Kategori(toko_id=toko_b.toko.id, nama="Kategori B")
    db_session.add(kategori_b)
    await db_session.commit()

    resp = await client.post(
        "/produk",
        headers=toko_a.headers,
        json={"nama": "Produk A", "kategori_id": str(kategori_b.id)},
    )
    assert resp.status_code == 404


async def test_resep_tolak_varian_milik_produk_lain(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    # resep = fitur tingkat 1 (Pro) - toko_a default Gratis akan kena gate
    # fitur dulu (403) sebelum sampai ke pengecekan kepemilikan varian yg
    # mau diuji di sini, jadi pakai toko Bisnis lokal.
    toko_a = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    produk_utama = await buat_produk(db_session, toko_a.toko.id, nama="Nasi Goreng")
    produk_lain = await buat_produk(db_session, toko_a.toko.id, nama="Produk Lain")
    bahan = await buat_produk(db_session, toko_a.toko.id, nama="Beras")
    varian_produk_lain = ProdukVarian(produk_id=produk_lain.id, nama="Varian Produk Lain")
    db_session.add(varian_produk_lain)
    await db_session.commit()

    resp = await client.post(
        f"/produk/{produk_utama.id}/resep",
        headers=toko_a.headers,
        json={"bahan_id": str(bahan.id), "varian_id": str(varian_produk_lain.id), "qty": "0.1"},
    )
    assert resp.status_code == 404


async def test_bundling_tolak_varian_milik_produk_lain(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    # bundling = fitur tingkat 2 (Bisnis).
    toko_a = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    paket = await buat_produk(db_session, toko_a.toko.id, nama="Paket Hemat")
    isi = await buat_produk(db_session, toko_a.toko.id, nama="Isi Paket")
    produk_lain = await buat_produk(db_session, toko_a.toko.id, nama="Produk Lain")
    varian_produk_lain = ProdukVarian(produk_id=produk_lain.id, nama="Varian Produk Lain")
    db_session.add(varian_produk_lain)
    await db_session.commit()

    resp = await client.post(
        f"/produk/{paket.id}/bundling",
        headers=toko_a.headers,
        json={"produk_id": str(isi.id), "varian_id": str(varian_produk_lain.id), "qty": "1"},
    )
    assert resp.status_code == 404


async def test_harga_grosir_tolak_outlet_milik_toko_lain(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    # harga_grosir = fitur tingkat 2 (Bisnis).
    toko_a = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    toko_b = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    produk_a = await buat_produk(db_session, toko_a.toko.id)

    resp = await client.post(
        f"/produk/{produk_a.id}/harga-grosir",
        headers=toko_a.headers,
        json={"outlet_id": str(toko_b.outlet.id), "min_qty": "10", "harga": "1000"},
    )
    assert resp.status_code == 404


async def test_harga_outlet_tolak_varian_milik_produk_lain(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    produk_a = await buat_produk(db_session, toko_a.toko.id)
    produk_lain = await buat_produk(db_session, toko_a.toko.id, nama="Produk Lain")
    varian_produk_lain = ProdukVarian(produk_id=produk_lain.id, nama="Varian Produk Lain")
    db_session.add(varian_produk_lain)
    await db_session.commit()

    resp = await client.post(
        f"/produk/{produk_a.id}/harga-outlet",
        headers=toko_a.headers,
        json={"outlet_id": str(toko_a.outlet.id), "varian_id": str(varian_produk_lain.id), "harga_jual": "1000"},
    )
    assert resp.status_code == 404


async def test_antrean_nomor_tolak_perangkat_milik_toko_lain(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    # nomor_antrean = fitur tingkat 2 (Bisnis).
    toko_a = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    toko_b = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    perangkat_b = await buat_perangkat(db_session, toko_b.toko.id, toko_b.outlet.id, device_uid="device-b-1")

    resp = await client.post(
        "/antrean/nomor",
        headers=toko_a.headers,
        params={"outlet_id": str(toko_a.outlet.id), "perangkat_id": str(perangkat_b.id)},
    )
    assert resp.status_code == 404


async def test_refund_tolak_metode_bayar_milik_toko_lain(
    client: AsyncClient, db_session: AsyncSession, toko_a, toko_b
) -> None:
    produk_a = await buat_produk(db_session, toko_a.toko.id, harga_jual=Decimal("15000"))
    metode_a = await buat_metode_bayar(db_session, toko_a.toko.id)
    metode_b = await buat_metode_bayar(db_session, toko_b.toko.id)

    checkout_resp = await client.post(
        "/transaksi",
        headers=toko_a.headers,
        json=_checkout_body(
            outlet_id=toko_a.outlet.id, produk_id=produk_a.id, metode_bayar_id=metode_a.id,
            nomor_struk="OUT1-REFUND1", harga="15000",
        ),
    )
    assert checkout_resp.status_code == 201
    transaksi_id = checkout_resp.json()["id"]

    from app.models.transaksi import ItemTransaksi

    item_transaksi = (
        await db_session.execute(select(ItemTransaksi).where(ItemTransaksi.transaksi_id == uuid.UUID(transaksi_id)))
    ).scalars().first()

    resp = await client.post(
        f"/transaksi/{transaksi_id}/refund",
        headers=toko_a.headers,
        json={
            "alasan": "test",
            "metode_bayar_id": str(metode_b.id),
            "items": [{"item_transaksi_id": str(item_transaksi.id), "qty": "1"}],
        },
    )
    assert resp.status_code == 404
