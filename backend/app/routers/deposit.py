"""Deposit pelanggan / pendapatan diterima di muka (IMOGI no. 79).

Buku mutasi sederhana per pelanggan: `topup` menambah saldo (uang diterima di muka, belum jadi pendapatan),
`pakai` mengurangi saat pelanggan memakai deposit (kasir mencatatnya manual; belum jadi metode bayar di kasir),
`koreksi` mengurangi untuk perbaikan (catatan wajib). Saldo tidak boleh minus. Total saldo semua pelanggan =
kewajiban toko (pendapatan diterima di muka)."""

import uuid
from decimal import Decimal

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_db
from app.core.deps import get_pengguna_id, get_role_id, get_toko_id
from app.models.deposit import DepositPelanggan
from app.models.pelanggan import Pelanggan
from app.models.transaksi import MetodeBayar
from app.services.audit_service import catat_audit
from app.services.fitur_service import require_fitur
from app.services.izin_service import has_izin

router = APIRouter(prefix="/deposit", tags=["deposit"], dependencies=[Depends(require_fitur("prepaid_revenue"))])

_JENIS = ("topup", "pakai", "koreksi")


class DepositIn(BaseModel):
    pelanggan_id: uuid.UUID
    jenis: str
    jumlah: Decimal = Field(gt=0, le=Decimal("999999999999"))
    metode_bayar_id: uuid.UUID | None = None
    catatan: str | None = Field(default=None, max_length=300)


class DepositOut(BaseModel):
    id: uuid.UUID
    saldo_baru: Decimal


class MutasiOut(BaseModel):
    id: uuid.UUID
    jenis: str
    jumlah: Decimal
    catatan: str | None
    dibuat: str


class SaldoPelangganOut(BaseModel):
    pelanggan_id: uuid.UUID
    nama: str
    saldo: Decimal
    riwayat: list[MutasiOut]


class SaldoBarisOut(BaseModel):
    pelanggan_id: uuid.UUID
    nama: str
    saldo: Decimal


class RingkasanDepositOut(BaseModel):
    total_saldo: Decimal
    jumlah_pelanggan: int
    pelanggan: list[SaldoBarisOut]


def _bertanda(jenis: str, jumlah: Decimal) -> Decimal:
    return jumlah if jenis == "topup" else -jumlah


async def _wajib_izin(db: AsyncSession, role_id: uuid.UUID) -> None:
    if not await has_izin(db, role_id, "pelanggan.kelola"):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Role ini tidak punya izin pelanggan.kelola")


async def _pelanggan_milik_toko(db: AsyncSession, pelanggan_id: uuid.UUID, toko_id: uuid.UUID) -> Pelanggan:
    p = await db.get(Pelanggan, pelanggan_id)
    if p is None or p.toko_id != toko_id or p.deleted_at is not None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Pelanggan tidak ditemukan")
    return p


async def _mutasi(db: AsyncSession, toko_id: uuid.UUID, pelanggan_id: uuid.UUID | None = None) -> list[DepositPelanggan]:
    q = select(DepositPelanggan).where(DepositPelanggan.toko_id == toko_id, DepositPelanggan.deleted_at.is_(None))
    if pelanggan_id is not None:
        q = q.where(DepositPelanggan.pelanggan_id == pelanggan_id)
    return list((await db.execute(q.order_by(DepositPelanggan.created_at.desc()))).scalars().all())


@router.post("", response_model=DepositOut, status_code=status.HTTP_201_CREATED)
async def catat_deposit(
    body: DepositIn,
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> DepositOut:
    await _wajib_izin(db, role_id)
    if body.jenis not in _JENIS:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, "Jenis harus topup, pakai, atau koreksi")
    await _pelanggan_milik_toko(db, body.pelanggan_id, toko_id)
    if body.metode_bayar_id is not None:
        metode = await db.get(MetodeBayar, body.metode_bayar_id)
        if metode is None or metode.toko_id != toko_id:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Metode pembayaran tidak ditemukan")
    catatan = (body.catatan or "").strip() or None
    if body.jenis == "koreksi" and catatan is None:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, "Koreksi wajib diberi catatan")

    saldo = sum((_bertanda(m.jenis, Decimal(m.jumlah)) for m in await _mutasi(db, toko_id, body.pelanggan_id)), Decimal("0"))
    if body.jenis != "topup" and body.jumlah > saldo:
        raise HTTPException(status.HTTP_409_CONFLICT, f"Saldo deposit tidak cukup (tersisa {saldo})")
    baris = DepositPelanggan(
        toko_id=toko_id,
        pelanggan_id=body.pelanggan_id,
        jenis=body.jenis,
        jumlah=body.jumlah,
        metode_bayar_id=body.metode_bayar_id if body.jenis == "topup" else None,
        catatan=catatan,
        dibuat_oleh=pengguna_id,
    )
    db.add(baris)
    await db.flush()
    await catat_audit(
        db, toko_id=toko_id, pengguna_id=pengguna_id, aksi=f"deposit_{body.jenis}", tabel="deposit_pelanggan",
        record_id=baris.id, data_baru={"pelanggan_id": str(body.pelanggan_id), "jumlah": str(body.jumlah)},
    )
    await db.commit()
    return DepositOut(id=baris.id, saldo_baru=saldo + _bertanda(body.jenis, body.jumlah))


@router.get("/ringkasan", response_model=RingkasanDepositOut)
async def ringkasan(
    toko_id: uuid.UUID = Depends(get_toko_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> RingkasanDepositOut:
    await _wajib_izin(db, role_id)
    saldo: dict[uuid.UUID, Decimal] = {}
    for m in await _mutasi(db, toko_id):
        saldo[m.pelanggan_id] = saldo.get(m.pelanggan_id, Decimal("0")) + _bertanda(m.jenis, Decimal(m.jumlah))
    ada = {k: v for k, v in saldo.items() if v > 0}
    nama: dict[uuid.UUID, str] = {}
    if ada:
        for p in (await db.execute(select(Pelanggan).where(Pelanggan.id.in_(list(ada))))).scalars():
            nama[p.id] = p.nama
    baris = sorted(
        (SaldoBarisOut(pelanggan_id=k, nama=nama.get(k, "?"), saldo=v) for k, v in ada.items()), key=lambda b: -b.saldo
    )
    return RingkasanDepositOut(
        total_saldo=sum((b.saldo for b in baris), Decimal("0")), jumlah_pelanggan=len(baris), pelanggan=baris
    )


@router.get("/pelanggan/{pelanggan_id}", response_model=SaldoPelangganOut)
async def saldo_pelanggan(
    pelanggan_id: uuid.UUID,
    toko_id: uuid.UUID = Depends(get_toko_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> SaldoPelangganOut:
    await _wajib_izin(db, role_id)
    p = await _pelanggan_milik_toko(db, pelanggan_id, toko_id)
    mutasi = await _mutasi(db, toko_id, pelanggan_id)
    return SaldoPelangganOut(
        pelanggan_id=p.id,
        nama=p.nama,
        saldo=sum((_bertanda(m.jenis, Decimal(m.jumlah)) for m in mutasi), Decimal("0")),
        riwayat=[
            MutasiOut(id=m.id, jenis=m.jenis, jumlah=Decimal(m.jumlah), catatan=m.catatan, dibuat=m.created_at.isoformat())
            for m in mutasi[:100]
        ],
    )
