"""Laporan keuangan sederhana standar UMKM (IMOGI no. 81; arahan lead 2026-11-25: "yang simpel saja, standar UMKM").

Tanpa jurnal umum: semua angka disusun dari data yang sudah dicatat aplikasi dan dipetakan ke bagan akun standar
(services/coa_standar.py). Tiga bagian:
1. Laba rugi per akun untuk periode [dari, sampai] (sama dengan Laba rugi, ditambah penyusutan aset tetap).
2. Arus kas sederhana untuk periode yang sama: uang masuk dan keluar yang tercatat.
3. Posisi keuangan (neraca) ringkas per hari ini.

Batasan yang disengaja (ditampilkan juga di aplikasi):
- Kas & bank di neraca = akumulasi arus kas yang tercatat di aplikasi sejak awal; saldo sebelum memakai aplikasi,
  setoran modal, dan prive pemilik tidak tercatat.
- Modal & laba (ekuitas) = aset dikurangi kewajiban, tidak dipisah antara modal disetor dan laba ditahan.
- Utang pajak tidak dihitung karena setoran pajak belum dicatat aplikasi."""

import uuid
from datetime import UTC, date, datetime, time, timedelta
from decimal import Decimal

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_db
from app.core.deps import get_role_id, get_toko_id
from app.models.aset_tetap import AsetTetap
from app.models.deposit import DepositPelanggan
from app.models.pengeluaran import Pengeluaran
from app.models.produk import Produk
from app.models.stok import Pembelian, Stok
from app.models.transaksi import MetodeBayar, Pembayaran, Refund, Transaksi
from app.routers.aset_tetap import hitung_penyusutan
from app.services.coa_standar import AKUN_KATEGORI_PENGELUARAN, AKUN_PER_KODE
from app.services.fitur_service import require_fitur
from app.services.izin_service import has_izin
from app.services.laba_rugi_service import laba_rugi

router = APIRouter(
    prefix="/laporan-keuangan", tags=["laporan-keuangan"], dependencies=[Depends(require_fitur("ledger"))]
)

_MAKS_HARI = 366
_NOL = Decimal("0")


class BarisAkunOut(BaseModel):
    kode_akun: str
    nama: str
    jumlah: Decimal


class LabaRugiAkunOut(BaseModel):
    pendapatan: list[BarisAkunOut]
    total_pendapatan: Decimal
    hpp: list[BarisAkunOut]
    total_hpp: Decimal
    laba_kotor: Decimal
    beban: list[BarisAkunOut]
    total_beban: Decimal
    laba_bersih: Decimal


class BarisArusOut(BaseModel):
    keterangan: str
    kode_akun: str = ""
    jumlah: Decimal


class ArusKasOut(BaseModel):
    masuk: list[BarisArusOut]
    total_masuk: Decimal
    keluar: list[BarisArusOut]
    total_keluar: Decimal
    kenaikan_kas: Decimal


class PosisiKeuanganOut(BaseModel):
    per_tanggal: date
    aset: list[BarisAkunOut]
    total_aset: Decimal
    kewajiban: list[BarisAkunOut]
    total_kewajiban: Decimal
    ekuitas: Decimal


class LaporanKeuanganOut(BaseModel):
    dari: date
    sampai: date
    laba_rugi: LabaRugiAkunOut
    arus_kas: ArusKasOut
    posisi: PosisiKeuanganOut


def _baris(kode: str, jumlah: Decimal) -> BarisAkunOut:
    return BarisAkunOut(kode_akun=kode, nama=AKUN_PER_KODE[kode].nama, jumlah=jumlah)


def _gabung(baris: list[BarisAkunOut]) -> list[BarisAkunOut]:
    """Satukan baris berkode sama, buang yang nol, urutkan menurut kode akun."""
    per_kode: dict[str, Decimal] = {}
    for b in baris:
        per_kode[b.kode_akun] = per_kode.get(b.kode_akun, _NOL) + b.jumlah
    return [_baris(k, v) for k, v in sorted(per_kode.items()) if v != 0]


async def _penyusutan_periode(db: AsyncSession, toko_id: uuid.UUID, dari: date, sampai: date) -> Decimal:
    aset = (await db.execute(select(AsetTetap).where(AsetTetap.toko_id == toko_id, AsetTetap.deleted_at.is_(None)))).scalars().all()
    total = _NOL
    for a in aset:
        akhir = hitung_penyusutan(a, sampai).akumulasi_penyusutan
        awal = hitung_penyusutan(a, dari.replace(day=1) - timedelta(days=1)).akumulasi_penyusutan
        total += akhir - awal
    return total


async def _arus_kas(
    db: AsyncSession, toko_id: uuid.UUID, awal: datetime, akhir: datetime, tgl_awal: date | None, tgl_akhir: date
) -> ArusKasOut:
    """Uang masuk/keluar yang tercatat pada [awal, akhir). awal None = sejak awal data (dipakai untuk saldo kas)."""

    def rentang(kolom):
        kondisi = [kolom < akhir]
        if awal is not None:
            kondisi.append(kolom >= awal)
        return kondisi

    ts_bayar = func.coalesce(Pembayaran.dibayar_pada, Pembayaran.created_at)
    penerimaan = (
        await db.execute(
            select(MetodeBayar.nama, func.coalesce(func.sum(Pembayaran.jumlah), 0))
            .join(Transaksi, Transaksi.id == Pembayaran.transaksi_id)
            .join(MetodeBayar, MetodeBayar.id == Pembayaran.metode_bayar_id)
            .where(Transaksi.toko_id == toko_id, Pembayaran.status == "berhasil", *rentang(ts_bayar))
            .group_by(MetodeBayar.nama)
        )
    ).all()
    masuk = [BarisArusOut(keterangan=f"Penjualan - {nama}", jumlah=Decimal(str(j))) for nama, j in penerimaan if j]

    topup = await db.scalar(
        select(func.coalesce(func.sum(DepositPelanggan.jumlah), 0)).where(
            DepositPelanggan.toko_id == toko_id, DepositPelanggan.deleted_at.is_(None), DepositPelanggan.jenis == "topup", *rentang(DepositPelanggan.created_at)
        )
    )
    if topup:
        masuk.append(BarisArusOut(keterangan="Deposit pelanggan diterima", jumlah=Decimal(str(topup))))

    q_biaya = select(Pengeluaran.kategori, func.sum(Pengeluaran.jumlah)).where(
        Pengeluaran.toko_id == toko_id, Pengeluaran.deleted_at.is_(None), Pengeluaran.tanggal <= tgl_akhir
    )
    if tgl_awal is not None:
        q_biaya = q_biaya.where(Pengeluaran.tanggal >= tgl_awal)
    keluar = [
        BarisArusOut(
            keterangan=AKUN_PER_KODE[AKUN_KATEGORI_PENGELUARAN.get(k, "6-9000")].nama,
            kode_akun=AKUN_KATEGORI_PENGELUARAN.get(k, "6-9000"),
            jumlah=Decimal(str(j)),
        )
        for k, j in (await db.execute(q_biaya.group_by(Pengeluaran.kategori))).all()
        if j
    ]
    refund = await db.scalar(
        select(func.coalesce(func.sum(Refund.kas_dikembalikan), 0))
        .join(Transaksi, Transaksi.id == Refund.transaksi_id)
        .where(Transaksi.toko_id == toko_id, *rentang(Refund.created_at))
    )
    if refund:
        keluar.append(BarisArusOut(keterangan="Uang dikembalikan (refund)", jumlah=Decimal(str(refund))))
    q_aset = select(func.coalesce(func.sum(AsetTetap.harga_perolehan), 0)).where(
        AsetTetap.toko_id == toko_id, AsetTetap.deleted_at.is_(None), AsetTetap.tanggal_perolehan <= tgl_akhir
    )
    if tgl_awal is not None:
        q_aset = q_aset.where(AsetTetap.tanggal_perolehan >= tgl_awal)
    beli_aset = await db.scalar(q_aset)
    if beli_aset:
        keluar.append(BarisArusOut(keterangan="Pembelian aset tetap", jumlah=Decimal(str(beli_aset))))
    q_pemasok = select(func.coalesce(func.sum(Pembelian.total), 0)).where(
        Pembelian.toko_id == toko_id, Pembelian.status == "diterima", Pembelian.status_bayar == "lunas",
        Pembelian.tanggal <= tgl_akhir,
    )
    if tgl_awal is not None:
        q_pemasok = q_pemasok.where(Pembelian.tanggal >= tgl_awal)
    bayar_pemasok = await db.scalar(q_pemasok)
    if bayar_pemasok:
        keluar.append(BarisArusOut(keterangan="Pembayaran ke pemasok", jumlah=Decimal(str(bayar_pemasok))))

    total_masuk = sum((b.jumlah for b in masuk), _NOL)
    total_keluar = sum((b.jumlah for b in keluar), _NOL)
    return ArusKasOut(
        masuk=masuk, total_masuk=total_masuk, keluar=keluar, total_keluar=total_keluar, kenaikan_kas=total_masuk - total_keluar
    )


async def _posisi(db: AsyncSession, toko_id: uuid.UUID, hari_ini: date) -> PosisiKeuanganOut:
    besok = datetime.combine(hari_ini + timedelta(days=1), time.min, tzinfo=UTC)
    kas = (await _arus_kas(db, toko_id, None, besok, None, hari_ini)).kenaikan_kas

    piutang = await db.scalar(
        select(func.coalesce(func.sum(Transaksi.sisa_tagihan), 0)).where(
            Transaksi.toko_id == toko_id,
            Transaksi.status == "selesai",
            Transaksi.status_bayar != "lunas",
            Transaksi.deleted_at.is_(None),
        )
    )
    persediaan = await db.scalar(
        select(func.coalesce(func.sum(Stok.jumlah * func.coalesce(func.nullif(Stok.hpp_rata_rata, 0), Produk.hpp)), 0))
        .join(Produk, Produk.id == Stok.produk_id)
        .where(Produk.toko_id == toko_id, Produk.deleted_at.is_(None), Stok.jumlah > 0)
    )
    aset_tetap = (await db.execute(select(AsetTetap).where(AsetTetap.toko_id == toko_id, AsetTetap.deleted_at.is_(None)))).scalars().all()
    harga_aset = sum((Decimal(a.harga_perolehan) for a in aset_tetap), _NOL)
    akumulasi = sum((hitung_penyusutan(a, hari_ini).akumulasi_penyusutan for a in aset_tetap), _NOL)

    aset = _gabung([
        _baris("1-1100", kas),
        _baris("1-1300", Decimal(str(piutang or 0))),
        _baris("1-1400", Decimal(str(persediaan or 0)).quantize(Decimal("0.01"))),
        _baris("1-2100", harga_aset),
        _baris("1-2200", -akumulasi),
    ])

    deposit = _NOL
    for jenis, jumlah in (
        await db.execute(
            select(DepositPelanggan.jenis, func.sum(DepositPelanggan.jumlah))
            .where(DepositPelanggan.toko_id == toko_id, DepositPelanggan.deleted_at.is_(None))
            .group_by(DepositPelanggan.jenis)
        )
    ).all():
        deposit += Decimal(str(jumlah)) if jenis == "topup" else -Decimal(str(jumlah))
    utang_pemasok = await db.scalar(
        select(func.coalesce(func.sum(Pembelian.total), 0)).where(
            Pembelian.toko_id == toko_id, Pembelian.status == "diterima", Pembelian.status_bayar != "lunas"
        )
    )
    kewajiban = _gabung([_baris("2-1100", Decimal(str(utang_pemasok or 0))), _baris("2-1300", deposit)])

    total_aset = sum((b.jumlah for b in aset), _NOL)
    total_kewajiban = sum((b.jumlah for b in kewajiban), _NOL)
    return PosisiKeuanganOut(
        per_tanggal=hari_ini,
        aset=aset,
        total_aset=total_aset,
        kewajiban=kewajiban,
        total_kewajiban=total_kewajiban,
        ekuitas=total_aset - total_kewajiban,
    )


@router.get("", response_model=LaporanKeuanganOut)
async def laporan_keuangan(
    dari: date = Query(...),
    sampai: date = Query(...),
    toko_id: uuid.UUID = Depends(get_toko_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> LaporanKeuanganOut:
    if not await has_izin(db, role_id, "laporan.lihat"):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Role ini tidak punya izin laporan.lihat")
    if sampai < dari:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, "Tanggal sampai harus sesudah dari")
    if (sampai - dari).days > _MAKS_HARI:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, f"Rentang maksimal {_MAKS_HARI} hari")

    awal = datetime.combine(dari, time.min, tzinfo=UTC)
    akhir = datetime.combine(sampai + timedelta(days=1), time.min, tzinfo=UTC)

    lr = await laba_rugi(db, toko_id=toko_id, outlet_id=None, dari=awal, sampai=akhir)
    pendapatan = _gabung([_baris("4-1000", lr.penjualan_kotor), _baris("4-2000", -lr.diskon)])
    hpp = _gabung([_baris("5-1000", lr.hpp)])
    beban_baris = []
    for b in lr.biaya_operasional:
        kode = AKUN_KATEGORI_PENGELUARAN.get(b.kategori, "6-9000")
        # Kemasan tercatat sebagai HPP kemasan; sisanya beban usaha.
        (hpp if AKUN_PER_KODE[kode].kelompok == "hpp" else beban_baris).append(_baris(kode, b.total))
    hpp = _gabung(hpp)
    penyusutan = await _penyusutan_periode(db, toko_id, dari, sampai)
    beban_baris.append(_baris("6-1600", penyusutan))
    beban = _gabung(beban_baris)
    total_pendapatan = sum((b.jumlah for b in pendapatan), _NOL)
    total_hpp = sum((b.jumlah for b in hpp), _NOL)
    total_beban = sum((b.jumlah for b in beban), _NOL)
    laba_kotor = total_pendapatan - total_hpp

    return LaporanKeuanganOut(
        dari=dari,
        sampai=sampai,
        laba_rugi=LabaRugiAkunOut(
            pendapatan=pendapatan,
            total_pendapatan=total_pendapatan,
            hpp=hpp,
            total_hpp=total_hpp,
            laba_kotor=laba_kotor,
            beban=beban,
            total_beban=total_beban,
            laba_bersih=laba_kotor - total_beban,
        ),
        arus_kas=await _arus_kas(db, toko_id, awal, akhir, dari, sampai),
        posisi=await _posisi(db, toko_id, datetime.now(UTC).date()),
    )
