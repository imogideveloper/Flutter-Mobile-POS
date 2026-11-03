"""Stok opname - HANYA di server (aturan dokumen #4.1). `qty_sistem`
diambil sbg SNAPSHOT saldo stok saat draft dibuat (bukan dihitung ulang
saat 'selesai') - itu memang maksud opname: bandingkan apa kata sistem
SAAT DIHITUNG vs fisiknya, walau ada transaksi lain yang masuk di
antaranya. Penyesuaian stok (mutasi_stok jenis 'opname') baru terjadi
saat status pindah ke 'selesai'."""

import uuid
from decimal import Decimal

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.outlet import Outlet
from app.models.produk import Produk
from app.models.stok import ItemOpname, Stok, StokOpname
from app.schemas.stok_opname import ItemOpnameOut, StokOpnameIn, StokOpnameOut
from app.services.kepemilikan import pastikan_produk_milik_toko
from app.services.stok_service import catat_mutasi


async def _saldo_stok(db: AsyncSession, outlet_id: uuid.UUID, produk_id: uuid.UUID, varian_id: uuid.UUID | None) -> Decimal:
    row = (
        await db.execute(
            select(Stok).where(Stok.outlet_id == outlet_id, Stok.produk_id == produk_id, Stok.varian_id == varian_id)
        )
    ).scalar_one_or_none()
    return row.jumlah if row is not None else Decimal("0")


async def buat_opname(
    db: AsyncSession, *, toko_id: uuid.UUID, pengguna_id: uuid.UUID, body: StokOpnameIn
) -> StokOpnameOut:
    if not body.items:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Minimal satu item opname")

    produk_ids = {item.produk_id for item in body.items}
    varian_ids = {item.varian_id for item in body.items if item.varian_id is not None}
    await pastikan_produk_milik_toko(db, produk_ids, toko_id, varian_ids=varian_ids)

    opname = StokOpname(
        outlet_id=body.outlet_id, nomor=body.nomor, tanggal=body.tanggal, status="draft",
        catatan=body.catatan, dibuat_oleh=pengguna_id,
    )
    db.add(opname)
    await db.flush()

    for item in body.items:
        qty_sistem = await _saldo_stok(db, body.outlet_id, item.produk_id, item.varian_id)
        db.add(
            ItemOpname(
                stok_opname_id=opname.id,
                produk_id=item.produk_id,
                varian_id=item.varian_id,
                qty_sistem=qty_sistem,
                qty_fisik=item.qty_fisik,
                selisih=item.qty_fisik - qty_sistem,
            )
        )

    await db.commit()
    return await opname_ke_out(db, opname)


async def selesaikan_opname(db: AsyncSession, *, opname: StokOpname, pengguna_id: uuid.UUID) -> StokOpnameOut:
    if opname.status != "draft":
        raise HTTPException(status.HTTP_409_CONFLICT, "Hanya opname 'draft' yang bisa diselesaikan")

    items = (
        await db.execute(select(ItemOpname).where(ItemOpname.stok_opname_id == opname.id))
    ).scalars().all()
    outlet = await db.get(Outlet, opname.outlet_id)

    for item in items:
        if item.selisih == 0:
            continue
        await catat_mutasi(
            db,
            toko_id=outlet.toko_id,
            outlet_id=opname.outlet_id,
            produk_id=item.produk_id,
            varian_id=item.varian_id,
            jenis="opname",
            qty=item.selisih,
            ref_tipe="stok_opname",
            ref_id=opname.id,
            dibuat_oleh=pengguna_id,
            catatan=f"Opname {opname.nomor}: sistem {item.qty_sistem} -> fisik {item.qty_fisik}",
        )

    opname.status = "selesai"
    opname.disetujui_oleh = pengguna_id
    await db.commit()
    return await opname_ke_out(db, opname)


async def opname_ke_out(db: AsyncSession, opname: StokOpname) -> StokOpnameOut:
    rows = (
        await db.execute(
            select(ItemOpname, Produk)
            .join(Produk, Produk.id == ItemOpname.produk_id)
            .where(ItemOpname.stok_opname_id == opname.id)
        )
    ).all()
    return StokOpnameOut(
        id=opname.id,
        outlet_id=opname.outlet_id,
        nomor=opname.nomor,
        tanggal=opname.tanggal,
        status=opname.status,
        items=[
            ItemOpnameOut(
                id=item.id, produk_id=item.produk_id, nama_produk=produk.nama, varian_id=item.varian_id,
                qty_sistem=item.qty_sistem, qty_fisik=item.qty_fisik, selisih=item.selisih,
            )
            for item, produk in rows
        ],
    )
