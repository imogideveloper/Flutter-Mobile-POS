"""Satu-satunya jalan masuk untuk mengubah stok: menulis baris mutasi_stok
lalu memperbarui saldo di tabel stok, dalam satu transaction DB yang sama
supaya keduanya selalu konsisten (port dari pola yang sudah ada & teruji
di app Flutter, StokDao.catatMutasi)."""

import uuid
from decimal import Decimal

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.stok import MutasiStok, Stok


async def catat_mutasi(
    db: AsyncSession,
    *,
    toko_id: uuid.UUID,
    outlet_id: uuid.UUID,
    produk_id: uuid.UUID,
    varian_id: uuid.UUID | None,
    jenis: str,
    qty: Decimal,  # + masuk, - keluar
    hpp_satuan: Decimal = Decimal("0"),
    ref_tipe: str | None = None,
    ref_id: uuid.UUID | None = None,
    catatan: str | None = None,
    dibuat_oleh: uuid.UUID | None = None,
) -> None:
    existing = (
        await db.execute(
            select(Stok).where(
                Stok.outlet_id == outlet_id,
                Stok.produk_id == produk_id,
                Stok.varian_id == varian_id,
            )
        )
    ).scalar_one_or_none()

    saldo_sebelum = existing.jumlah if existing is not None else Decimal("0")
    saldo_setelah = saldo_sebelum + qty

    if existing is None:
        db.add(
            Stok(
                outlet_id=outlet_id,
                produk_id=produk_id,
                varian_id=varian_id,
                jumlah=saldo_setelah,
            )
        )
    else:
        existing.jumlah = saldo_setelah

    db.add(
        MutasiStok(
            toko_id=toko_id,
            outlet_id=outlet_id,
            produk_id=produk_id,
            varian_id=varian_id,
            jenis=jenis,
            qty=qty,
            hpp_satuan=hpp_satuan,
            saldo_setelah=saldo_setelah,
            ref_tipe=ref_tipe,
            ref_id=ref_id,
            catatan=catatan,
            dibuat_oleh=dibuat_oleh,
        )
    )
