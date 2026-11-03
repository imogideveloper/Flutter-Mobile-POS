"""Modul 9 (sebagian): tiket dapur otomatis saat checkout + penghitung
nomor antrean harian.

Tiket dapur: item transaksi dikelompokkan per `stasiun_dapur` (lewat
produk -> kategori -> stasiun_dapur_id) jadi satu `pesanan_dapur` per
stasiun (bukan satu tiket per item) - item TANPA kategori/stasiun_dapur
masuk grup `None` (satu tiket umum, dicetak di printer kasir default).

Antrean harian: penghitung per (outlet, perangkat, tanggal) - baca baris
existing lewat `SELECT ... FOR UPDATE` (`with_for_update()`) supaya
request kedua yang datang bersamaan MENUNGGU request pertama commit dulu
baru baca nilai terbaru, bukan baca nilai basi lalu dua-duanya nulis
`nomor_terakhir` yang sama. SQLite (dipakai test) tidak punya row lock
sungguhan - `with_for_update()` di dialect itu jadi no-op (diverifikasi
tidak error), jadi test tetap jalan tapi tidak membuktikan locking-nya;
lock yang sungguhan hanya berlaku saat jalan di Postgres produksi."""

import uuid
from collections import defaultdict
from datetime import UTC, datetime

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.order import AntreanHarian, ItemPesananDapur, PesananDapur
from app.models.produk import Kategori, Produk
from app.models.transaksi import ItemTransaksi, Transaksi


async def buat_pesanan_dapur(db: AsyncSession, transaksi: Transaksi) -> list[PesananDapur]:
    items = (
        await db.execute(select(ItemTransaksi).where(ItemTransaksi.transaksi_id == transaksi.id))
    ).scalars().all()
    if not items:
        return []

    produk_ids = {item.produk_id for item in items}
    produk_rows = (await db.execute(select(Produk).where(Produk.id.in_(produk_ids)))).scalars().all()
    produk_by_id = {p.id: p for p in produk_rows}

    kategori_ids = {p.kategori_id for p in produk_rows if p.kategori_id is not None}
    kategori_rows = (
        (await db.execute(select(Kategori).where(Kategori.id.in_(kategori_ids)))).scalars().all()
        if kategori_ids
        else []
    )
    stasiun_by_kategori = {k.id: k.stasiun_dapur_id for k in kategori_rows}

    grup: dict[uuid.UUID | None, list[ItemTransaksi]] = defaultdict(list)
    for item in items:
        produk = produk_by_id.get(item.produk_id)
        kategori_id = produk.kategori_id if produk else None
        stasiun_id = stasiun_by_kategori.get(kategori_id) if kategori_id else None
        grup[stasiun_id].append(item)

    hasil: list[PesananDapur] = []
    for stasiun_id, item_grup in grup.items():
        pesanan = PesananDapur(
            transaksi_id=transaksi.id,
            stasiun_dapur_id=stasiun_id,
            urutan_kirim=1,
            status="baru",
        )
        db.add(pesanan)
        await db.flush()

        for item in item_grup:
            db.add(ItemPesananDapur(pesanan_dapur_id=pesanan.id, item_transaksi_id=item.id, qty=item.qty))

        hasil.append(pesanan)

    await db.commit()
    return hasil


async def ambil_nomor_antrean_berikutnya(
    db: AsyncSession, *, outlet_id: uuid.UUID, perangkat_id: uuid.UUID, prefix: str = ""
) -> AntreanHarian:
    hari_ini = datetime.now(UTC).date()

    row = (
        await db.execute(
            select(AntreanHarian)
            .where(
                AntreanHarian.outlet_id == outlet_id,
                AntreanHarian.perangkat_id == perangkat_id,
                AntreanHarian.tanggal == hari_ini,
            )
            .with_for_update()
        )
    ).scalar_one_or_none()
    if row is None:
        row = AntreanHarian(
            outlet_id=outlet_id, perangkat_id=perangkat_id, tanggal=hari_ini, prefix=prefix, nomor_terakhir=1
        )
        db.add(row)
    else:
        row.nomor_terakhir += 1

    await db.commit()
    await db.refresh(row)
    return row


def format_nomor_antrean(row: AntreanHarian) -> str:
    if row.prefix:
        return f"{row.prefix}-{row.nomor_terakhir:03d}"
    return f"{row.nomor_terakhir:03d}"
