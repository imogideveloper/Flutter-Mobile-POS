"""Mutasi stok manual dari HP (AT10, docs/perlu_konfirmasi.md): pembelian/opname/penyesuaian yang dicatat di
HP harus sampai ke server, tanpa menggandakan saldo bila dikirim ulang."""

import uuid
from decimal import Decimal

from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.stok import MutasiStok, Stok
from tests.conftest import buat_produk


async def _kirim(client: AsyncClient, toko, produk, *, jenis="pembelian", qty="10", id=None, **tambahan):
    return await client.post(
        "/stok/mutasi",
        headers=toko.headers,
        json={
            "id": str(id or uuid.uuid4()),
            "outlet_id": str(toko.outlet.id),
            "produk_id": str(produk.id),
            "jenis": jenis,
            "qty": qty,
            **tambahan,
        },
    )


async def _saldo(db: AsyncSession, toko, produk) -> Decimal:
    baris = (
        await db.execute(select(Stok).where(Stok.outlet_id == toko.outlet.id, Stok.produk_id == produk.id))
    ).scalar_one_or_none()
    return Decimal(str(baris.jumlah)) if baris else Decimal("0")


async def test_pembelian_manual_menambah_saldo_dan_mencatat_mutasi(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id)
    mid = uuid.uuid4()
    resp = await _kirim(client, toko_a, produk, id=mid, catatan="Uji pembelian roti")
    assert resp.status_code == 201, resp.text
    assert resp.json()["diterapkan"] is True
    assert Decimal(resp.json()["saldo_setelah"]) == Decimal("10")

    assert await _saldo(db_session, toko_a, produk) == Decimal("10")
    mutasi = await db_session.get(MutasiStok, mid)
    assert mutasi.jenis == "pembelian" and mutasi.catatan == "Uji pembelian roti"
    assert mutasi.dibuat_oleh == toko_a.pengguna.id


async def test_opname_negatif_mengurangi_saldo(client: AsyncClient, db_session: AsyncSession, toko_a) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id)
    await _kirim(client, toko_a, produk, qty="3")
    resp = await _kirim(client, toko_a, produk, jenis="opname", qty="-1")
    assert resp.status_code == 201, resp.text
    assert await _saldo(db_session, toko_a, produk) == Decimal("2")


async def test_kirim_ulang_id_sama_tidak_menggandakan_saldo(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id)
    mid = uuid.uuid4()
    assert (await _kirim(client, toko_a, produk, id=mid)).json()["diterapkan"] is True
    ulang = await _kirim(client, toko_a, produk, id=mid)
    assert ulang.status_code == 201
    assert ulang.json()["diterapkan"] is False
    assert await _saldo(db_session, toko_a, produk) == Decimal("10")


async def test_jenis_penjualan_refund_void_ditolak(client: AsyncClient, db_session: AsyncSession, toko_a) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id)
    for jenis in ("penjualan", "refund", "void"):
        resp = await _kirim(client, toko_a, produk, jenis=jenis, qty="-1")
        assert resp.status_code == 422, (jenis, resp.text)
    assert await _saldo(db_session, toko_a, produk) == Decimal("0")


async def test_qty_nol_ditolak(client: AsyncClient, db_session: AsyncSession, toko_a) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id)
    assert (await _kirim(client, toko_a, produk, qty="0")).status_code == 422


async def test_produk_toko_lain_ditolak(client: AsyncClient, db_session: AsyncSession, toko_a, toko_b) -> None:
    produk_b = await buat_produk(db_session, toko_b.toko.id)
    resp = await _kirim(client, toko_a, produk_b)
    assert resp.status_code == 404
    assert await _saldo(db_session, toko_b, produk_b) == Decimal("0")


async def test_outlet_toko_lain_ditolak(client: AsyncClient, db_session: AsyncSession, toko_a, toko_b) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id)
    resp = await client.post(
        "/stok/mutasi",
        headers=toko_a.headers,
        json={
            "id": str(uuid.uuid4()),
            "outlet_id": str(toko_b.outlet.id),
            "produk_id": str(produk.id),
            "jenis": "pembelian",
            "qty": "5",
        },
    )
    assert resp.status_code == 404


async def test_pencatat_mutasi_adalah_karyawan_yang_dikirim_bukan_pemilik_token(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    """Satu token perangkat dipakai bergilir: pengguna_id dari HP menentukan siapa yang tercatat mengubah stok."""
    from app.models.akun import AksesOutlet, Pengguna, Role

    role = (await db_session.execute(select(Role).where(Role.nama == "Gudang", Role.is_system.is_(True)))).scalar_one()
    gudang = Pengguna(toko_id=toko_a.toko.id, role_id=role.id, nama="Uji Gudang", no_hp="081200000077")
    db_session.add(gudang)
    await db_session.flush()
    db_session.add(AksesOutlet(pengguna_id=gudang.id, outlet_id=toko_a.outlet.id))
    await db_session.commit()

    produk = await buat_produk(db_session, toko_a.toko.id)
    mid = uuid.uuid4()
    resp = await _kirim(client, toko_a, produk, id=mid, pengguna_id=str(gudang.id))
    assert resp.status_code == 201, resp.text
    assert (await db_session.get(MutasiStok, mid)).dibuat_oleh == gudang.id


async def test_pencatat_dari_toko_lain_diabaikan_kembali_ke_pemilik_token(
    client: AsyncClient, db_session: AsyncSession, toko_a, toko_b
) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id)
    mid = uuid.uuid4()
    resp = await _kirim(client, toko_a, produk, id=mid, pengguna_id=str(toko_b.pengguna.id))
    assert resp.status_code == 201, resp.text
    assert (await db_session.get(MutasiStok, mid)).dibuat_oleh == toko_a.pengguna.id


async def test_tanpa_pengguna_id_tetap_pemilik_token(client: AsyncClient, db_session: AsyncSession, toko_a) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id)
    mid = uuid.uuid4()
    assert (await _kirim(client, toko_a, produk, id=mid)).status_code == 201
    assert (await db_session.get(MutasiStok, mid)).dibuat_oleh == toko_a.pengguna.id
