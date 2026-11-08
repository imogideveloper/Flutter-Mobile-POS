"""Helper terpusat utk memvalidasi bahwa suatu resource (outlet/produk/
varian/shift) sungguhan milik toko_id yang sedang login, SEBELUM dipakai
menulis data apa pun.

Latar belakang: audit menemukan beberapa service (checkout, transfer stok,
pembelian, buka shift, sync push) menerima id outlet/produk/shift dari body
klien lalu langsung menulis ke tabel Stok/MutasiStok (yang sendiri TIDAK
punya kolom toko_id) tanpa pernah mengecek kepemilikan - toko A bisa
menebak/mengenumerasi UUID milik toko B dan merusak stok/kas toko itu lewat
API resmi. Pola helper per-router yang sudah ada (`_pastikan_outlet_milik_toko`
di order.py/stok_opname.py, `ambil_produk_milik_toko` di produk.py) terbukti
TIDAK konsisten dipasang di semua service - makanya dipusatkan di sini, satu
sumber kebenaran yang dipanggil dari semua service yang menulis data
toko-scoped.

Semua helper di sini SENGAJA melempar 404 dengan pesan generik ("tidak
ditemukan") baik utk resource yang benar-benar tidak ada maupun yang ada
tapi milik toko lain - supaya response tidak membocorkan informasi bahwa
suatu id itu valid tapi kepunyaan toko lain (celah enumerasi)."""

import uuid
from collections.abc import Iterable

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.outlet import Outlet
from app.models.produk import Produk, ProdukVarian
from app.models.transaksi import Shift


async def get_outlet_milik_toko(session: AsyncSession, outlet_id: uuid.UUID, toko_id: uuid.UUID) -> Outlet:
    outlet = await session.get(Outlet, outlet_id)
    if outlet is None or outlet.toko_id != toko_id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Outlet tidak ditemukan")
    return outlet


async def pastikan_produk_milik_toko(
    session: AsyncSession,
    produk_ids: Iterable[uuid.UUID],
    toko_id: uuid.UUID,
    *,
    varian_ids: Iterable[uuid.UUID] | None = None,
) -> None:
    """Cek SEMUA produk_ids sekaligus dalam satu query (bukan satu query per
    id) - raise 404 kalau ada SATU PUN yang tidak ditemukan/bukan milik
    toko ini. `varian_ids` opsional - kalau diisi, divalidasi juga dalam
    satu query terpisah (varian tidak punya kolom toko_id sendiri, jadi
    divalidasi lewat join ke produk induknya)."""

    produk_ids = {p for p in produk_ids if p is not None}
    if produk_ids:
        ditemukan = set(
            (
                await session.execute(
                    select(Produk.id).where(Produk.id.in_(produk_ids), Produk.toko_id == toko_id)
                )
            )
            .scalars()
            .all()
        )
        if ditemukan != produk_ids:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Produk tidak ditemukan")

    varian_ids = {v for v in (varian_ids or []) if v is not None}
    if varian_ids:
        ditemukan_varian = set(
            (
                await session.execute(
                    select(ProdukVarian.id)
                    .join(Produk, Produk.id == ProdukVarian.produk_id)
                    .where(ProdukVarian.id.in_(varian_ids), Produk.toko_id == toko_id)
                )
            )
            .scalars()
            .all()
        )
        if ditemukan_varian != varian_ids:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Varian produk tidak ditemukan")


async def get_shift_aktif(
    session: AsyncSession,
    shift_id: uuid.UUID,
    toko_id: uuid.UUID,
    outlet_id: uuid.UUID,
    *,
    harus_buka: bool = True,
) -> Shift:
    """Shift harus milik toko DAN outlet yang sama dgn request yang sedang
    diproses, dan statusnya masih 'buka' - shift milik outlet/toko lain,
    atau yang sudah ditutup, tidak boleh dipakai checkout/transaksi baru."""

    shift = await session.get(Shift, shift_id)
    if (
        shift is None
        or shift.toko_id != toko_id
        or shift.outlet_id != outlet_id
        or (harus_buka and shift.status != "buka")
    ):
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Shift tidak ditemukan atau tidak aktif")
    return shift
