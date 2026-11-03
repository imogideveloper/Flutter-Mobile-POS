import uuid
from datetime import UTC, datetime
from decimal import Decimal

from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import create_access_token
from app.models.akun import Pengguna, Role
from app.models.audit import AuditLog
from app.models.stok import Stok
from app.models.transaksi import ItemTransaksi
from tests.conftest import buat_metode_bayar, buat_produk


async def _checkout_dua_item(client: AsyncClient, toko_a, produk, metode) -> str:
    resp = await client.post(
        "/transaksi",
        headers=toko_a.headers,
        json={
            "outlet_id": str(toko_a.outlet.id),
            "nomor_struk": "OUT1-R001",
            "tanggal": datetime.now(UTC).isoformat(),
            "items": [
                {"produk_id": str(produk.id), "nama_produk": produk.nama, "qty": "4", "harga_satuan": "15000"}
            ],
            "metode_bayar_id": str(metode.id),
            "total_bayar": "60000",
        },
    )
    assert resp.status_code == 201
    return resp.json()["id"]


async def _ambil_item_transaksi_id(db_session: AsyncSession, transaksi_id: str) -> str:
    item = (
        await db_session.execute(
            select(ItemTransaksi).where(ItemTransaksi.transaksi_id == uuid.UUID(transaksi_id))
        )
    ).scalars().first()
    return str(item.id)


async def test_refund_sebagian_lalu_refund_sisanya_jadi_lunas(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id, harga_jual=Decimal("15000"))
    metode = await buat_metode_bayar(db_session, toko_a.toko.id)
    transaksi_id = await _checkout_dua_item(client, toko_a, produk, metode)
    item_id = await _ambil_item_transaksi_id(db_session, transaksi_id)

    stok_awal = (await db_session.execute(select(Stok).where(Stok.produk_id == produk.id))).scalar_one()
    assert stok_awal.jumlah == Decimal("-4")

    resp1 = await client.post(
        f"/transaksi/{transaksi_id}/refund",
        headers=toko_a.headers,
        json={"alasan": "2 rusak", "items": [{"item_transaksi_id": item_id, "qty": "2"}]},
    )
    assert resp1.status_code == 201
    body1 = resp1.json()
    assert body1["total"] == "30000.00"
    assert body1["status_transaksi"] == "refund_sebagian"

    await db_session.refresh(stok_awal)
    assert stok_awal.jumlah == Decimal("-2")  # 2 dikembalikan

    # Refund sisa 2 lagi - transaksi harus jadi 'refund' penuh.
    resp2 = await client.post(
        f"/transaksi/{transaksi_id}/refund",
        headers=toko_a.headers,
        json={"alasan": "sisanya juga rusak", "items": [{"item_transaksi_id": item_id, "qty": "2"}]},
    )
    assert resp2.status_code == 201
    assert resp2.json()["status_transaksi"] == "refund"

    await db_session.refresh(stok_awal)
    assert stok_awal.jumlah == Decimal("0")

    daftar = await client.get(f"/transaksi/{transaksi_id}/refund", headers=toko_a.headers)
    assert len(daftar.json()) == 2


async def test_refund_melebihi_sisa_qty_ditolak(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id, harga_jual=Decimal("15000"))
    metode = await buat_metode_bayar(db_session, toko_a.toko.id)
    transaksi_id = await _checkout_dua_item(client, toko_a, produk, metode)
    item_id = await _ambil_item_transaksi_id(db_session, transaksi_id)

    resp = await client.post(
        f"/transaksi/{transaksi_id}/refund",
        headers=toko_a.headers,
        json={"alasan": "coba lebih dari qty", "items": [{"item_transaksi_id": item_id, "qty": "5"}]},
    )
    assert resp.status_code == 400


async def test_refund_tanpa_kembalikan_stok(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id, harga_jual=Decimal("15000"))
    metode = await buat_metode_bayar(db_session, toko_a.toko.id)
    transaksi_id = await _checkout_dua_item(client, toko_a, produk, metode)
    item_id = await _ambil_item_transaksi_id(db_session, transaksi_id)

    stok = (await db_session.execute(select(Stok).where(Stok.produk_id == produk.id))).scalar_one()
    assert stok.jumlah == Decimal("-4")

    resp = await client.post(
        f"/transaksi/{transaksi_id}/refund",
        headers=toko_a.headers,
        json={
            "alasan": "barang sudah dibuang, tidak boleh balik stok",
            "kembalikan_stok": False,
            "items": [{"item_transaksi_id": item_id, "qty": "1"}],
        },
    )
    assert resp.status_code == 201

    await db_session.refresh(stok)
    assert stok.jumlah == Decimal("-4"), "stok tidak boleh berubah kalau kembalikan_stok=false"


async def test_kasir_tanpa_izin_refund_ditolak(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id, harga_jual=Decimal("15000"))
    metode = await buat_metode_bayar(db_session, toko_a.toko.id)
    transaksi_id = await _checkout_dua_item(client, toko_a, produk, metode)
    item_id = await _ambil_item_transaksi_id(db_session, transaksi_id)

    kasir_role = (
        await db_session.execute(select(Role).where(Role.nama == "Kasir", Role.is_system.is_(True)))
    ).scalar_one()
    kasir = Pengguna(toko_id=toko_a.toko.id, role_id=kasir_role.id, nama="Kasir Biasa")
    db_session.add(kasir)
    await db_session.commit()
    token_kasir = create_access_token(pengguna_id=kasir.id, toko_id=toko_a.toko.id, role_id=kasir_role.id)

    resp = await client.post(
        f"/transaksi/{transaksi_id}/refund",
        headers={"Authorization": f"Bearer {token_kasir}"},
        json={"alasan": "Coba-coba", "items": [{"item_transaksi_id": item_id, "qty": "1"}]},
    )
    assert resp.status_code == 403


async def test_refund_tercatat_di_audit_log(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id, harga_jual=Decimal("15000"))
    metode = await buat_metode_bayar(db_session, toko_a.toko.id)
    transaksi_id = await _checkout_dua_item(client, toko_a, produk, metode)
    item_id = await _ambil_item_transaksi_id(db_session, transaksi_id)

    await client.post(
        f"/transaksi/{transaksi_id}/refund",
        headers=toko_a.headers,
        json={"alasan": "Salah ukuran", "items": [{"item_transaksi_id": item_id, "qty": "1"}]},
    )

    rows = (
        await db_session.execute(select(AuditLog).where(AuditLog.aksi == "refund"))
    ).scalars().all()
    assert len(rows) == 1


async def test_item_refundable_menghitung_sisa_setelah_refund_sebagian(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id, harga_jual=Decimal("15000"))
    metode = await buat_metode_bayar(db_session, toko_a.toko.id)
    transaksi_id = await _checkout_dua_item(client, toko_a, produk, metode)
    item_id = await _ambil_item_transaksi_id(db_session, transaksi_id)

    resp_awal = await client.get(f"/transaksi/{transaksi_id}/item-refundable", headers=toko_a.headers)
    assert resp_awal.status_code == 200
    assert Decimal(resp_awal.json()[0]["sisa_bisa_direfund"]) == 4

    await client.post(
        f"/transaksi/{transaksi_id}/refund",
        headers=toko_a.headers,
        json={"alasan": "1 rusak", "items": [{"item_transaksi_id": item_id, "qty": "1"}]},
    )

    resp_setelah = await client.get(f"/transaksi/{transaksi_id}/item-refundable", headers=toko_a.headers)
    assert resp_setelah.status_code == 200
    baris = resp_setelah.json()[0]
    assert Decimal(baris["qty_sudah_direfund"]) == 1
    assert Decimal(baris["sisa_bisa_direfund"]) == 3


async def test_refund_proporsional_penuh_sama_persis_dgn_total_transaksi(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    """F3.D.3 - refund SEMUA item dari transaksi berpajak harus menjumlah
    PERSIS sama dgn total yang dibayar pelanggan (bukan cuma qty*harga),
    walau pembagian largest-remainder per baris bisa ganjil."""
    produk_a = await buat_produk(db_session, toko_a.toko.id, nama="A", harga_jual=Decimal("9999"))
    produk_b = await buat_produk(db_session, toko_a.toko.id, nama="B", harga_jual=Decimal("5001"))
    metode = await buat_metode_bayar(db_session, toko_a.toko.id)
    await client.post("/pajak", headers=toko_a.headers, json={"nama": "PPN", "persen": "11", "urutan": 0})

    checkout = await client.post(
        "/transaksi",
        headers=toko_a.headers,
        json={
            "outlet_id": str(toko_a.outlet.id),
            "nomor_struk": "OUT1-R-PROP",
            "tanggal": datetime.now(UTC).isoformat(),
            "items": [
                {"produk_id": str(produk_a.id), "nama_produk": "A", "qty": "3", "harga_satuan": "9999"},
                {"produk_id": str(produk_b.id), "nama_produk": "B", "qty": "7", "harga_satuan": "5001"},
            ],
            "metode_bayar_id": str(metode.id),
            "total_bayar": "100000",
        },
    )
    assert checkout.status_code == 201
    total_transaksi = Decimal(checkout.json()["total"])
    transaksi_id = checkout.json()["id"]

    items = (
        await db_session.execute(
            select(ItemTransaksi).where(ItemTransaksi.transaksi_id == uuid.UUID(transaksi_id))
        )
    ).scalars().all()

    resp = await client.post(
        f"/transaksi/{transaksi_id}/refund",
        headers=toko_a.headers,
        json={
            "alasan": "batal semua",
            "items": [{"item_transaksi_id": str(i.id), "qty": str(i.qty)} for i in items],
        },
    )
    assert resp.status_code == 201
    assert Decimal(resp.json()["total"]) == total_transaksi


async def test_refund_push_offline_idempotent_berdasarkan_id(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id, harga_jual=Decimal("15000"))
    metode = await buat_metode_bayar(db_session, toko_a.toko.id)
    transaksi_id = await _checkout_dua_item(client, toko_a, produk, metode)
    item_id = await _ambil_item_transaksi_id(db_session, transaksi_id)
    refund_id = str(uuid.uuid4())

    payload = {
        "id": refund_id,
        "alasan": "offline",
        "items": [{"item_transaksi_id": item_id, "qty": "2"}],
    }
    resp1 = await client.post(f"/transaksi/{transaksi_id}/refund", headers=toko_a.headers, json=payload)
    assert resp1.status_code == 201

    resp2 = await client.post(f"/transaksi/{transaksi_id}/refund", headers=toko_a.headers, json=payload)
    assert resp2.status_code == 201
    assert resp2.json()["id"] == refund_id

    stok = (await db_session.execute(select(Stok).where(Stok.produk_id == produk.id))).scalar_one()
    assert stok.jumlah == Decimal("-2"), "push ulang refund yang sama tidak boleh mengembalikan stok dua kali"

    daftar = await client.get(f"/transaksi/{transaksi_id}/refund", headers=toko_a.headers)
    assert len(daftar.json()) == 1


async def test_refund_push_offline_melebihi_qty_dipotong_bukan_ditolak(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    """F3.D.5 - dua HP refund offline bersamaan, total minta melebihi qty:
    yang pertama (online, qty=3 dari 4) diterima penuh; push offline kedua
    (qty=2, sisa cuma 1) dipotong ke sisa yg valid + tercatat audit_log,
    BUKAN ditolak 400 (barang di HP kedua sudah kadung "kembali")."""
    produk = await buat_produk(db_session, toko_a.toko.id, harga_jual=Decimal("15000"))
    metode = await buat_metode_bayar(db_session, toko_a.toko.id)
    transaksi_id = await _checkout_dua_item(client, toko_a, produk, metode)
    item_id = await _ambil_item_transaksi_id(db_session, transaksi_id)

    pertama = await client.post(
        f"/transaksi/{transaksi_id}/refund",
        headers=toko_a.headers,
        json={"alasan": "refund pertama", "items": [{"item_transaksi_id": item_id, "qty": "3"}]},
    )
    assert pertama.status_code == 201

    kedua = await client.post(
        f"/transaksi/{transaksi_id}/refund",
        headers=toko_a.headers,
        json={
            "id": str(uuid.uuid4()),
            "alasan": "refund kedua (offline, device belum tahu yg pertama)",
            "items": [{"item_transaksi_id": item_id, "qty": "2"}],
        },
    )
    assert kedua.status_code == 201
    item_refund_kedua = kedua.json()["items"][0]
    assert Decimal(item_refund_kedua["qty"]) == 1, "cuma sisa valid (1) yg diterima, bukan 2 yg diminta"

    log_rows = (
        await db_session.execute(
            select(AuditLog).where(AuditLog.aksi == "refund_offline_melebihi_qty")
        )
    ).scalars().all()
    assert len(log_rows) == 1
