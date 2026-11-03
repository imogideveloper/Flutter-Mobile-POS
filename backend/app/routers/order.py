"""Modul 9: tipe_order (toko-scoped), meja & stasiun_dapur (outlet-scoped,
divalidasi outlet-nya milik toko dari token), tiket dapur, antrean harian."""

import uuid
from datetime import UTC, datetime

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_db
from app.core.deps import get_pengguna_id, get_role_id, get_toko_id, require_outlet_access
from app.models.order import ItemPesananDapur, Meja, PesananDapur, StasiunDapur, TipeOrder, TipeOrderPajak
from app.models.outlet import Outlet, Perangkat
from app.models.promo import Pajak
from app.models.transaksi import ItemTransaksi, Transaksi
from app.schemas.order import (
    AntreanNomorOut,
    ItemPesananDapurOut,
    MejaIn,
    MejaOut,
    MejaUpdateIn,
    PesananDapurOut,
    StasiunDapurIn,
    StasiunDapurOut,
    TipeOrderIn,
    TipeOrderOut,
    TipeOrderPajakOut,
    TipeOrderUpdateIn,
    UbahStatusPesananDapurIn,
)
from app.services.audit_service import catat_audit
from app.services.fitur_service import require_fitur
from app.services.izin_service import has_izin
from app.services.order_service import ambil_nomor_antrean_berikutnya, format_nomor_antrean

router = APIRouter(tags=["order-dapur"])


async def _pastikan_outlet_milik_toko(db: AsyncSession, outlet_id: uuid.UUID, toko_id: uuid.UUID) -> None:
    outlet = await db.get(Outlet, outlet_id)
    if outlet is None or outlet.toko_id != toko_id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Outlet tidak ditemukan")


async def _wajib_izin_pengaturan_kelola(db: AsyncSession, role_id: uuid.UUID) -> None:
    if not await has_izin(db, role_id, "pengaturan.kelola"):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Role ini tidak punya izin pengaturan.kelola")


@router.get("/tipe-order", response_model=list[TipeOrderOut], dependencies=[Depends(require_fitur("tipe_order"))])
async def daftar_tipe_order(
    toko_id: uuid.UUID = Depends(get_toko_id), db: AsyncSession = Depends(get_db)
) -> list[TipeOrder]:
    rows = (
        await db.execute(
            select(TipeOrder)
            .where(TipeOrder.toko_id == toko_id, TipeOrder.deleted_at.is_(None))
            .order_by(TipeOrder.urutan)
        )
    ).scalars().all()
    return list(rows)


@router.post(
    "/tipe-order", response_model=TipeOrderOut, status_code=status.HTTP_201_CREATED,
    dependencies=[Depends(require_fitur("tipe_order"))],
)
async def tambah_tipe_order(
    body: TipeOrderIn,
    toko_id: uuid.UUID = Depends(get_toko_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> TipeOrder:
    await _wajib_izin_pengaturan_kelola(db, role_id)
    tipe = TipeOrder(toko_id=toko_id, **body.model_dump())
    db.add(tipe)
    await db.commit()
    await db.refresh(tipe)
    return tipe


async def _ambil_tipe_order_milik_toko(db: AsyncSession, tipe_order_id: uuid.UUID, toko_id: uuid.UUID) -> TipeOrder:
    tipe = await db.get(TipeOrder, tipe_order_id)
    if tipe is None or tipe.toko_id != toko_id or tipe.deleted_at is not None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Tipe order tidak ditemukan")
    return tipe


@router.patch(
    "/tipe-order/{tipe_order_id}", response_model=TipeOrderOut, dependencies=[Depends(require_fitur("tipe_order"))]
)
async def ubah_tipe_order(
    tipe_order_id: uuid.UUID,
    body: TipeOrderUpdateIn,
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> TipeOrder:
    await _wajib_izin_pengaturan_kelola(db, role_id)
    tipe = await _ambil_tipe_order_milik_toko(db, tipe_order_id, toko_id)
    perubahan = body.model_dump(exclude_unset=True)
    data_lama = {k: str(getattr(tipe, k)) for k in perubahan}
    for field, value in perubahan.items():
        setattr(tipe, field, value)
    await catat_audit(
        db, toko_id=toko_id, pengguna_id=pengguna_id, aksi="ubah_tipe_order",
        tabel="tipe_order", record_id=tipe.id,
        data_lama=data_lama, data_baru={k: str(v) for k, v in perubahan.items()},
    )
    await db.commit()
    await db.refresh(tipe)
    return tipe


@router.delete(
    "/tipe-order/{tipe_order_id}", status_code=status.HTTP_204_NO_CONTENT,
    dependencies=[Depends(require_fitur("tipe_order"))],
)
async def hapus_tipe_order(
    tipe_order_id: uuid.UUID,
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> None:
    await _wajib_izin_pengaturan_kelola(db, role_id)
    tipe = await _ambil_tipe_order_milik_toko(db, tipe_order_id, toko_id)
    tipe.deleted_at = datetime.now(UTC)
    await catat_audit(
        db, toko_id=toko_id, pengguna_id=pengguna_id, aksi="hapus_tipe_order",
        tabel="tipe_order", record_id=tipe.id, data_lama={"nama": tipe.nama},
    )
    await db.commit()


@router.get(
    "/tipe-order/{tipe_order_id}/pajak", response_model=list[TipeOrderPajakOut],
    dependencies=[Depends(require_fitur("service_per_tipe_order"))],
)
async def daftar_tipe_order_pajak(
    tipe_order_id: uuid.UUID, toko_id: uuid.UUID = Depends(get_toko_id), db: AsyncSession = Depends(get_db)
) -> list[TipeOrderPajakOut]:
    await _ambil_tipe_order_milik_toko(db, tipe_order_id, toko_id)
    rows = (
        await db.execute(
            select(TipeOrderPajak, Pajak)
            .join(Pajak, Pajak.id == TipeOrderPajak.pajak_id)
            .where(TipeOrderPajak.tipe_order_id == tipe_order_id)
        )
    ).all()
    return [
        TipeOrderPajakOut(tipe_order_id=top.tipe_order_id, pajak_id=top.pajak_id, nama_pajak=pajak.nama)
        for top, pajak in rows
    ]


@router.post(
    "/tipe-order/{tipe_order_id}/pajak/{pajak_id}", status_code=status.HTTP_204_NO_CONTENT,
    dependencies=[Depends(require_fitur("service_per_tipe_order"))],
)
async def tautkan_tipe_order_pajak(
    tipe_order_id: uuid.UUID,
    pajak_id: uuid.UUID,
    toko_id: uuid.UUID = Depends(get_toko_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> None:
    await _wajib_izin_pengaturan_kelola(db, role_id)
    await _ambil_tipe_order_milik_toko(db, tipe_order_id, toko_id)
    pajak = await db.get(Pajak, pajak_id)
    if pajak is None or pajak.toko_id != toko_id or pajak.deleted_at is not None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Pajak tidak ditemukan")

    existing = await db.get(TipeOrderPajak, {"tipe_order_id": tipe_order_id, "pajak_id": pajak_id})
    if existing is None:
        db.add(TipeOrderPajak(tipe_order_id=tipe_order_id, pajak_id=pajak_id))
        await db.commit()


@router.delete(
    "/tipe-order/{tipe_order_id}/pajak/{pajak_id}", status_code=status.HTTP_204_NO_CONTENT,
    dependencies=[Depends(require_fitur("service_per_tipe_order"))],
)
async def lepas_tipe_order_pajak(
    tipe_order_id: uuid.UUID,
    pajak_id: uuid.UUID,
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> None:
    await _wajib_izin_pengaturan_kelola(db, role_id)
    await _ambil_tipe_order_milik_toko(db, tipe_order_id, toko_id)
    link = await db.get(TipeOrderPajak, {"tipe_order_id": tipe_order_id, "pajak_id": pajak_id})
    if link is None:
        return
    await catat_audit(
        db, toko_id=toko_id, pengguna_id=pengguna_id, aksi="lepas_tipe_order_pajak",
        tabel="tipe_order_pajak", record_id=tipe_order_id, data_lama={"pajak_id": str(pajak_id)},
    )
    await db.delete(link)
    await db.commit()


@router.get("/outlets/{outlet_id}/meja", response_model=list[MejaOut])
async def daftar_meja(
    outlet_id: uuid.UUID,
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> list[Meja]:
    await _pastikan_outlet_milik_toko(db, outlet_id, toko_id)
    await require_outlet_access(db, pengguna_id=pengguna_id, role_id=role_id, outlet_id=outlet_id)
    rows = (
        await db.execute(
            select(Meja).where(Meja.outlet_id == outlet_id, Meja.deleted_at.is_(None)).order_by(Meja.urutan)
        )
    ).scalars().all()
    return list(rows)


@router.post("/outlets/{outlet_id}/meja", response_model=MejaOut, status_code=status.HTTP_201_CREATED)
async def tambah_meja(
    outlet_id: uuid.UUID,
    body: MejaIn,
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> Meja:
    await _pastikan_outlet_milik_toko(db, outlet_id, toko_id)
    await require_outlet_access(db, pengguna_id=pengguna_id, role_id=role_id, outlet_id=outlet_id)
    await _wajib_izin_pengaturan_kelola(db, role_id)
    meja = Meja(outlet_id=outlet_id, **body.model_dump())
    db.add(meja)
    await db.commit()
    await db.refresh(meja)
    return meja


async def _ambil_meja_milik_outlet(db: AsyncSession, meja_id: uuid.UUID, outlet_id: uuid.UUID) -> Meja:
    meja = await db.get(Meja, meja_id)
    if meja is None or meja.outlet_id != outlet_id or meja.deleted_at is not None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Meja tidak ditemukan")
    return meja


@router.patch("/outlets/{outlet_id}/meja/{meja_id}", response_model=MejaOut)
async def ubah_meja(
    outlet_id: uuid.UUID,
    meja_id: uuid.UUID,
    body: MejaUpdateIn,
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> Meja:
    await _pastikan_outlet_milik_toko(db, outlet_id, toko_id)
    await require_outlet_access(db, pengguna_id=pengguna_id, role_id=role_id, outlet_id=outlet_id)
    await _wajib_izin_pengaturan_kelola(db, role_id)
    meja = await _ambil_meja_milik_outlet(db, meja_id, outlet_id)

    perubahan = body.model_dump(exclude_unset=True)
    data_lama = {k: str(getattr(meja, k)) for k in perubahan}
    for field, value in perubahan.items():
        setattr(meja, field, value)
    await catat_audit(
        db, toko_id=toko_id, pengguna_id=pengguna_id, aksi="ubah_meja",
        tabel="meja", record_id=meja.id,
        data_lama=data_lama, data_baru={k: str(v) for k, v in perubahan.items()},
    )
    await db.commit()
    await db.refresh(meja)
    return meja


@router.delete("/outlets/{outlet_id}/meja/{meja_id}", status_code=status.HTTP_204_NO_CONTENT)
async def hapus_meja(
    outlet_id: uuid.UUID,
    meja_id: uuid.UUID,
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> None:
    await _pastikan_outlet_milik_toko(db, outlet_id, toko_id)
    await require_outlet_access(db, pengguna_id=pengguna_id, role_id=role_id, outlet_id=outlet_id)
    await _wajib_izin_pengaturan_kelola(db, role_id)
    meja = await _ambil_meja_milik_outlet(db, meja_id, outlet_id)
    meja.deleted_at = datetime.now(UTC)
    await catat_audit(
        db, toko_id=toko_id, pengguna_id=pengguna_id, aksi="hapus_meja",
        tabel="meja", record_id=meja.id, data_lama={"nama": meja.nama},
    )
    await db.commit()


@router.get("/outlets/{outlet_id}/stasiun-dapur", response_model=list[StasiunDapurOut])
async def daftar_stasiun_dapur(
    outlet_id: uuid.UUID,
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> list[StasiunDapur]:
    await _pastikan_outlet_milik_toko(db, outlet_id, toko_id)
    await require_outlet_access(db, pengguna_id=pengguna_id, role_id=role_id, outlet_id=outlet_id)
    rows = (
        await db.execute(select(StasiunDapur).where(StasiunDapur.outlet_id == outlet_id, StasiunDapur.deleted_at.is_(None)))
    ).scalars().all()
    return list(rows)


@router.post(
    "/outlets/{outlet_id}/stasiun-dapur", response_model=StasiunDapurOut, status_code=status.HTTP_201_CREATED
)
async def tambah_stasiun_dapur(
    outlet_id: uuid.UUID,
    body: StasiunDapurIn,
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> StasiunDapur:
    await _pastikan_outlet_milik_toko(db, outlet_id, toko_id)
    await require_outlet_access(db, pengguna_id=pengguna_id, role_id=role_id, outlet_id=outlet_id)
    stasiun = StasiunDapur(outlet_id=outlet_id, **body.model_dump())
    db.add(stasiun)
    await db.commit()
    await db.refresh(stasiun)
    return stasiun


async def _pesanan_dapur_ke_out(db: AsyncSession, pesanan: PesananDapur) -> PesananDapurOut:
    item_rows = (
        await db.execute(
            select(ItemPesananDapur, ItemTransaksi)
            .join(ItemTransaksi, ItemTransaksi.id == ItemPesananDapur.item_transaksi_id)
            .where(ItemPesananDapur.pesanan_dapur_id == pesanan.id)
        )
    ).all()
    return PesananDapurOut(
        id=pesanan.id,
        transaksi_id=pesanan.transaksi_id,
        stasiun_dapur_id=pesanan.stasiun_dapur_id,
        urutan_kirim=pesanan.urutan_kirim,
        status=pesanan.status,
        dicetak_pada=pesanan.dicetak_pada,
        siap_pada=pesanan.siap_pada,
        items=[
            ItemPesananDapurOut(item_transaksi_id=it.id, nama_produk=it.nama_produk, qty=ipd.qty)
            for ipd, it in item_rows
        ],
    )


@router.get("/dapur/pesanan", response_model=list[PesananDapurOut])
async def daftar_pesanan_dapur(
    outlet_id: uuid.UUID,
    status_pesanan: str | None = None,
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> list[PesananDapurOut]:
    await _pastikan_outlet_milik_toko(db, outlet_id, toko_id)
    await require_outlet_access(db, pengguna_id=pengguna_id, role_id=role_id, outlet_id=outlet_id)
    query = (
        select(PesananDapur)
        .join(Transaksi, Transaksi.id == PesananDapur.transaksi_id)
        .where(Transaksi.outlet_id == outlet_id)
    )
    if status_pesanan is not None:
        query = query.where(PesananDapur.status == status_pesanan)
    rows = (await db.execute(query.order_by(PesananDapur.created_at))).scalars().all()
    return [await _pesanan_dapur_ke_out(db, r) for r in rows]


async def _ambil_pesanan_dapur_milik_toko(
    db: AsyncSession, pesanan_id: uuid.UUID, toko_id: uuid.UUID
) -> PesananDapur:
    row = (
        await db.execute(
            select(PesananDapur)
            .join(Transaksi, Transaksi.id == PesananDapur.transaksi_id)
            .where(PesananDapur.id == pesanan_id, Transaksi.toko_id == toko_id)
        )
    ).scalar_one_or_none()
    if row is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Pesanan dapur tidak ditemukan")
    return row


@router.patch("/dapur/pesanan/{pesanan_id}/status", response_model=PesananDapurOut)
async def ubah_status_pesanan_dapur(
    pesanan_id: uuid.UUID,
    body: UbahStatusPesananDapurIn,
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> PesananDapurOut:
    pesanan = await _ambil_pesanan_dapur_milik_toko(db, pesanan_id, toko_id)
    transaksi = await db.get(Transaksi, pesanan.transaksi_id)
    await require_outlet_access(db, pengguna_id=pengguna_id, role_id=role_id, outlet_id=transaksi.outlet_id)
    pesanan.status = body.status
    if body.status == "siap":
        pesanan.siap_pada = datetime.now(UTC)
    await db.commit()
    await db.refresh(pesanan)
    return await _pesanan_dapur_ke_out(db, pesanan)


@router.post("/antrean/nomor", response_model=AntreanNomorOut, dependencies=[Depends(require_fitur("nomor_antrean"))])
async def nomor_antrean_berikutnya(
    outlet_id: uuid.UUID,
    perangkat_id: uuid.UUID,
    prefix: str = "",
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> AntreanNomorOut:
    await _pastikan_outlet_milik_toko(db, outlet_id, toko_id)
    await require_outlet_access(db, pengguna_id=pengguna_id, role_id=role_id, outlet_id=outlet_id)

    perangkat = await db.get(Perangkat, perangkat_id)
    if perangkat is None or perangkat.toko_id != toko_id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Perangkat tidak ditemukan")

    row = await ambil_nomor_antrean_berikutnya(db, outlet_id=outlet_id, perangkat_id=perangkat_id, prefix=prefix)
    return AntreanNomorOut(
        tanggal=row.tanggal,
        prefix=row.prefix,
        nomor_terakhir=row.nomor_terakhir,
        nomor_lengkap=format_nomor_antrean(row),
    )
