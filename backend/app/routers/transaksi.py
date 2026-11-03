import uuid
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_db
from app.core.deps import get_pengguna_id, get_role_id, get_toko_id, require_outlet_access
from app.models.transaksi import ItemRefund, Refund, Transaksi
from app.schemas.pembayaran import PembayaranIn, PembayaranOut
from app.schemas.refund import ItemRefundableOut, ItemRefundOut, RefundIn, RefundOut
from app.schemas.transaksi import CheckoutIn, CheckoutOut, TransaksiListOut, TransaksiOut, VoidIn
from app.services.audit_service import catat_audit
from app.services.checkout_service import checkout as checkout_service
from app.services.izin_service import has_izin
from app.services.kepemilikan import get_outlet_milik_toko
from app.services.pembayaran_service import catat_pembayaran
from app.services.refund_service import buat_refund, daftar_item_refundable
from app.services.void_service import void_transaksi

router = APIRouter(prefix="/transaksi", tags=["transaksi"])


@router.post("", response_model=CheckoutOut, status_code=status.HTTP_201_CREATED)
async def buat_transaksi(
    body: CheckoutIn,
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> CheckoutOut:
    return await checkout_service(db, toko_id=toko_id, pengguna_id=pengguna_id, role_id=role_id, body=body)


@router.get("", response_model=TransaksiListOut)
async def daftar_transaksi(
    outlet_id: uuid.UUID | None = None,
    # Filter rentang tanggal (F3.B) - dipakai HP saat RiwayatListPage minta
    # data lebih lama drpd yang tersimpan lokal. Batas inklusif kedua sisi.
    dari_tanggal: datetime | None = None,
    sampai_tanggal: datetime | None = None,
    limit: int = Query(default=100, ge=1, le=200),
    offset: int = Query(default=0, ge=0),
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> TransaksiListOut:
    if outlet_id is not None:
        await get_outlet_milik_toko(db, outlet_id, toko_id)
        await require_outlet_access(db, pengguna_id=pengguna_id, role_id=role_id, outlet_id=outlet_id)

    query = select(Transaksi).where(Transaksi.toko_id == toko_id, Transaksi.deleted_at.is_(None))
    if outlet_id is not None:
        query = query.where(Transaksi.outlet_id == outlet_id)
    if dari_tanggal is not None:
        query = query.where(Transaksi.tanggal >= dari_tanggal)
    if sampai_tanggal is not None:
        query = query.where(Transaksi.tanggal <= sampai_tanggal)

    # Trik limit+1 (sama pola dgn /sync/pull paging) - ambil satu lebih
    # byk drpd limit utk tahu has_more tanpa query count terpisah.
    query = query.order_by(Transaksi.tanggal.desc()).offset(offset).limit(limit + 1)
    rows = (await db.execute(query)).scalars().all()
    has_more = len(rows) > limit
    return TransaksiListOut(items=list(rows[:limit]), has_more=has_more)


async def _ambil_transaksi_milik_toko(transaksi_id: uuid.UUID, toko_id: uuid.UUID, db: AsyncSession) -> Transaksi:
    transaksi = await db.get(Transaksi, transaksi_id)
    if transaksi is None or transaksi.toko_id != toko_id or transaksi.deleted_at is not None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Transaksi tidak ditemukan")
    return transaksi


@router.get("/{transaksi_id}", response_model=TransaksiOut)
async def detail_transaksi(
    transaksi_id: uuid.UUID,
    toko_id: uuid.UUID = Depends(get_toko_id),
    db: AsyncSession = Depends(get_db),
) -> Transaksi:
    return await _ambil_transaksi_milik_toko(transaksi_id, toko_id, db)


@router.post("/{transaksi_id}/void", response_model=TransaksiOut)
async def void(
    transaksi_id: uuid.UUID,
    body: VoidIn,
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> Transaksi:
    # Aturan dokumen #7: aksi sensitif wajib dicek izin role + dicatat di
    # audit_log. Beda dengan app Flutter (yang bisa minta PIN owner/manajer
    # kalau kasir tidak punya izin), di sini TIDAK ada alur approval PIN
    # lintas-pengguna - itu sudah terjadi di HP sebelum transaksi di-push
    # ke sini. Server HANYA menolak kalau pemilik token memang tidak
    # berwenang sama sekali.
    if not await has_izin(db, role_id, "transaksi.void"):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Role ini tidak punya izin transaksi.void")

    transaksi = await _ambil_transaksi_milik_toko(transaksi_id, toko_id, db)
    sebelum = {"status": transaksi.status}
    transaksi = await void_transaksi(db, transaksi=transaksi, alasan=body.alasan, disetujui_oleh=pengguna_id)

    await catat_audit(
        db,
        toko_id=toko_id,
        pengguna_id=pengguna_id,
        aksi="void",
        tabel="transaksi",
        record_id=transaksi.id,
        data_lama=sebelum,
        data_baru={"status": transaksi.status, "alasan_void": transaksi.alasan_void},
    )
    await db.commit()
    return transaksi


@router.get("/{transaksi_id}/item-refundable", response_model=list[ItemRefundableOut])
async def item_refundable(
    transaksi_id: uuid.UUID,
    toko_id: uuid.UUID = Depends(get_toko_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> list[dict]:
    if not await has_izin(db, role_id, "transaksi.refund"):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Role ini tidak punya izin transaksi.refund")
    await _ambil_transaksi_milik_toko(transaksi_id, toko_id, db)
    return await daftar_item_refundable(db, transaksi_id)


@router.post("/{transaksi_id}/refund", response_model=RefundOut, status_code=status.HTTP_201_CREATED)
async def refund(
    transaksi_id: uuid.UUID,
    body: RefundIn,
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> RefundOut:
    if not await has_izin(db, role_id, "transaksi.refund"):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Role ini tidak punya izin transaksi.refund")

    transaksi = await _ambil_transaksi_milik_toko(transaksi_id, toko_id, db)
    sebelum = {"status": transaksi.status}
    hasil = await buat_refund(db, toko_id=toko_id, transaksi=transaksi, pengguna_id=pengguna_id, body=body)

    await catat_audit(
        db,
        toko_id=toko_id,
        pengguna_id=pengguna_id,
        aksi="refund",
        tabel="transaksi",
        record_id=transaksi.id,
        data_lama=sebelum,
        data_baru={"status": transaksi.status, "refund_id": str(hasil.id), "total_refund": str(hasil.total)},
    )
    await db.commit()

    item_rows = (
        await db.execute(select(ItemRefund).where(ItemRefund.refund_id == hasil.id))
    ).scalars().all()
    return RefundOut(
        id=hasil.id,
        transaksi_id=transaksi.id,
        nomor=hasil.nomor,
        alasan=hasil.alasan,
        total=hasil.total,
        kas_dikembalikan=hasil.kas_dikembalikan,
        kembalikan_stok=hasil.kembalikan_stok,
        items=[ItemRefundOut(item_transaksi_id=r.item_transaksi_id, qty=r.qty, jumlah=r.jumlah) for r in item_rows],
        status_transaksi=transaksi.status,
        sisa_tagihan=transaksi.sisa_tagihan,
    )


@router.post(
    "/{transaksi_id}/pembayaran", response_model=PembayaranOut, status_code=status.HTTP_201_CREATED
)
async def bayar_cicilan(
    transaksi_id: uuid.UUID,
    body: PembayaranIn,
    toko_id: uuid.UUID = Depends(get_toko_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> PembayaranOut:
    # Dicatat kasir yang sama yang boleh membuat transaksi (izin
    # 'transaksi.buat') - tidak ada izin baru khusus kasbon (keputusan
    # tahap 3b-1, lihat laporan akhir).
    if not await has_izin(db, role_id, "transaksi.buat"):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Role ini tidak punya izin transaksi.buat")

    transaksi = await _ambil_transaksi_milik_toko(transaksi_id, toko_id, db)
    pembayaran = await catat_pembayaran(db, toko_id=toko_id, transaksi=transaksi, body=body)
    return PembayaranOut(
        id=pembayaran.id,
        transaksi_id=pembayaran.transaksi_id,
        shift_id=pembayaran.shift_id,
        metode_bayar_id=pembayaran.metode_bayar_id,
        jumlah=pembayaran.jumlah,
        jenis=pembayaran.jenis,
        status=pembayaran.status,
        dibayar_pada=pembayaran.dibayar_pada,
        sisa_tagihan=transaksi.sisa_tagihan,
        status_bayar=transaksi.status_bayar,
    )


@router.get("/{transaksi_id}/refund", response_model=list[RefundOut])
async def daftar_refund_transaksi(
    transaksi_id: uuid.UUID,
    toko_id: uuid.UUID = Depends(get_toko_id),
    db: AsyncSession = Depends(get_db),
) -> list[RefundOut]:
    transaksi = await _ambil_transaksi_milik_toko(transaksi_id, toko_id, db)
    refund_rows = (
        await db.execute(select(Refund).where(Refund.transaksi_id == transaksi.id))
    ).scalars().all()

    hasil: list[RefundOut] = []
    for r in refund_rows:
        item_rows = (
            await db.execute(select(ItemRefund).where(ItemRefund.refund_id == r.id))
        ).scalars().all()
        hasil.append(
            RefundOut(
                id=r.id,
                transaksi_id=transaksi.id,
                nomor=r.nomor,
                alasan=r.alasan,
                total=r.total,
                kas_dikembalikan=r.kas_dikembalikan,
                kembalikan_stok=r.kembalikan_stok,
                items=[
                    ItemRefundOut(item_transaksi_id=ir.item_transaksi_id, qty=ir.qty, jumlah=ir.jumlah)
                    for ir in item_rows
                ],
                status_transaksi=transaksi.status,
                sisa_tagihan=transaksi.sisa_tagihan,
            )
        )
    return hasil
