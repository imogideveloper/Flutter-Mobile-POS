"""Gating fitur per paket langganan (aturan dokumen #4.2): app HP boleh
cek lokal utk tampilan, tapi server WAJIB cek ulang di setiap endpoint
terkait - `require_fitur` di sini adalah dependency yang dipasang di
router lain utk itu.

Sumber kebenaran "paket X dapat fitur Y" adalah baris di `paket_fitur`,
BUKAN sekadar perbandingan `fitur.tingkat <= paket.urutan` (biar bisa
diubah tanpa update app, sesuai dokumen) - walau baris paket_fitur-nya
sendiri awalnya diisi otomatis dari perbandingan itu saat seed."""

import calendar
import math
import uuid
from dataclasses import dataclass
from datetime import UTC, datetime

from fastapi import Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_db
from app.core.deps import get_toko_id
from app.models.fitur import Fitur, PaketFitur
from app.models.outlet import Langganan, Paket, Toko
from app.services.platform_service import KUNCI_USIA_AKUN_BULAN, ambil_int


@dataclass(frozen=True)
class TrialInfo:
    """Masa trial berdasarkan usia akun toko (arahan lead 2026-11-08)."""

    mulai: datetime
    berakhir: datetime
    durasi_bulan: int
    aktif: bool
    hari_tersisa: int  # dibulatkan ke atas; 0 bila sudah berakhir


def _utc(dt: datetime) -> datetime:
    return dt if dt.tzinfo is not None else dt.replace(tzinfo=UTC)


def tambah_bulan(dt: datetime, bulan: int) -> datetime:
    """Tambah bulan KALENDER (31 Okt + 4 bulan = 28/29 Feb bila perlu)."""
    total = dt.month - 1 + bulan
    tahun = dt.year + total // 12
    bln = total % 12 + 1
    hari = min(dt.day, calendar.monthrange(tahun, bln)[1])
    return dt.replace(year=tahun, month=bln, day=hari)


async def trial_toko(db: AsyncSession, toko_id: uuid.UUID) -> TrialInfo | None:
    """Info masa trial toko, atau None bila fitur trial mati (pengaturan
    `usia_akun_bulan` tidak ada atau 0). Usia akun dihitung dari
    `toko.created_at` (tanggal toko mendaftar) - toko yang sudah ada ikut
    dihitung dari tanggal pembuatannya."""

    bulan = await ambil_int(db, KUNCI_USIA_AKUN_BULAN, 0)
    if bulan <= 0:
        return None
    toko = await db.get(Toko, toko_id)
    if toko is None:
        return None

    mulai = _utc(toko.created_at)
    berakhir = tambah_bulan(mulai, bulan)
    sekarang = datetime.now(UTC)
    aktif = sekarang < berakhir
    hari = math.ceil((berakhir - sekarang).total_seconds() / 86400) if aktif else 0
    return TrialInfo(mulai=mulai, berakhir=berakhir, durasi_bulan=bulan, aktif=aktif, hari_tersisa=hari)


async def paket_tertinggi(db: AsyncSession) -> Paket | None:
    """Paket aktif dengan `urutan` tertinggi (kini Bisnis; bila katalog
    diganti ke Imogi, otomatis Enterprise) - dipakai masa trial supaya
    logika tidak bergantung pada NAMA paket."""

    return (
        await db.execute(select(Paket).where(Paket.aktif.is_(True)).order_by(Paket.urutan.desc()))
    ).scalars().first()


async def langganan_aktif_toko(db: AsyncSession, toko_id: uuid.UUID) -> Langganan | None:
    """Baris Langganan yang SUNGGUH aktif sekarang (status='aktif' DAN
    belum lewat `berakhir`) - None kalau toko efektif Gratis. Dipakai
    bareng paket_aktif_toko kalau pemanggil butuh field langganan sendiri
    (mis. jumlah_outlet di outlet_service.py), bukan cuma Paket-nya.
    Temuan#3 (rapikan F3) - diekstrak dari paket_aktif_toko supaya KEDUA
    pemanggil memakai definisi "aktif" yang SAMA PERSIS (termasuk cek
    `berakhir`, tidak cuma `status`), bukan dua query mirip yang bisa
    diam2 melenceng."""

    now = datetime.now(UTC)
    return (
        await db.execute(
            select(Langganan)
            .where(
                Langganan.toko_id == toko_id,
                Langganan.status == "aktif",
                (Langganan.berakhir.is_(None)) | (Langganan.berakhir > now),
            )
            .order_by(Langganan.mulai.desc())
        )
    ).scalars().first()


async def paket_aktif_toko(db: AsyncSession, toko_id: uuid.UUID) -> Paket | None:
    """Paket dari langganan yang sungguh2 aktif - None kalau tidak ada.
    JANGAN dipakai langsung utk gating/kuota, pakai `paket_efektif` (di
    bawah) supaya toko yang langganannya kedaluwarsa otomatis turun ke
    Gratis, bukan "tanpa batas apa pun"."""

    langganan = await langganan_aktif_toko(db, toko_id)
    if langganan is None:
        return None
    return await db.get(Paket, langganan.paket_id)


async def paket_efektif(db: AsyncSession, toko_id: uuid.UUID) -> Paket:
    """Paket yang BENAR-BENAR berlaku sekarang: paket langganan aktif,
    atau 'Gratis' kalau toko tidak punya langganan aktif atau langganannya
    sudah lewat `berakhir`. Data toko TIDAK PERNAH dihapus saat
    kedaluwarsa - cuma fitur berbayarnya yang terkunci lagi. Semua
    pemanggil gating/kuota/`sync.pull` WAJIB lewat sini, bukan
    `paket_aktif_toko` langsung."""

    paket = await paket_aktif_toko(db, toko_id)
    if paket is None:
        # Paket TERENDAH (urutan terkecil: Gratis/Free) - dicari lewat urutan,
        # bukan nama, supaya tidak bergantung pada katalog yang dipakai.
        paket = (
            await db.execute(select(Paket).where(Paket.aktif.is_(True)).order_by(Paket.urutan.asc()))
        ).scalars().first()
        if paket is None:
            raise RuntimeError("Tidak ada paket aktif di database - seed belum jalan?")

    # Masa trial (arahan lead 2026-11-08): selama usia akun belum mencapai
    # batas, toko mendapat paket TERTINGGI tanpa pembatasan. Kalau toko
    # sudah berlangganan paket yang sama atau lebih tinggi, tidak berubah.
    trial = await trial_toko(db, toko_id)
    if trial is not None and trial.aktif:
        tertinggi = await paket_tertinggi(db)
        if tertinggi is not None and tertinggi.urutan > paket.urutan:
            return tertinggi
    return paket


async def kode_fitur_toko(db: AsyncSession, toko_id: uuid.UUID) -> set[str]:
    """Semua kode fitur yang terbuka utk toko ini - dipakai HP saat pull
    sync utk tahu fitur mana yang boleh ditampilkan (lihat
    toko.pengaturan_fitur di dokumen bagian 4.2)."""

    paket = await paket_efektif(db, toko_id)

    rows = (
        await db.execute(
            select(Fitur.kode).join(PaketFitur, PaketFitur.fitur_id == Fitur.id).where(PaketFitur.paket_id == paket.id)
        )
    ).scalars().all()
    return set(rows)


async def has_fitur(db: AsyncSession, toko_id: uuid.UUID, kode: str) -> bool:
    return kode in await kode_fitur_toko(db, toko_id)


async def semua_batas_fitur_toko(db: AsyncSession, toko_id: uuid.UUID) -> dict[str, int]:
    """Semua {kode_fitur: batas} yang PUNYA batas (bukan NULL) di paket
    efektif toko ini - dikirim lewat /sync/pull (lihat SyncPullOut.batas_fitur)
    supaya app lokal tahu fitur mana yang terbuka TAPI dibatasi."""

    paket = await paket_efektif(db, toko_id)
    rows = (
        await db.execute(
            select(Fitur.kode, PaketFitur.batas)
            .join(PaketFitur, PaketFitur.fitur_id == Fitur.id)
            .where(PaketFitur.paket_id == paket.id, PaketFitur.batas.is_not(None))
        )
    ).all()
    return {kode: batas for kode, batas in rows}


async def batas_fitur_toko(db: AsyncSession, toko_id: uuid.UUID, kode: str) -> int | None:
    """Nilai `paket_fitur.batas` utk fitur `kode` di paket EFEKTIF toko
    ini. None kalau fitur-nya tidak terbuka ATAU terbuka TANPA batas -
    pemanggil (mis. laporan_service) WAJIB cek has_fitur/kode_fitur_toko
    dulu kalau None di sini harus dibedakan antara "tanpa batas" dan
    "fitur tidak terbuka sama sekali"."""

    paket = await paket_efektif(db, toko_id)
    row = (
        await db.execute(
            select(PaketFitur.batas)
            .join(Fitur, Fitur.id == PaketFitur.fitur_id)
            .where(PaketFitur.paket_id == paket.id, Fitur.kode == kode)
        )
    ).scalar_one_or_none()
    return row


async def paket_minimal_untuk_fitur(db: AsyncSession, kode: str) -> str | None:
    """Nama paket TERMURAH yang membuka fitur ini - dibaca dari baris
    `paket_fitur` yang SUNGGUHAN ada (bukan cuma `fitur.tingkat`), persis
    sesuai prinsip "sumber kebenaran paket_fitur, bisa diubah tanpa update
    app" di docstring modul ini. None kalau fitur ini tidak terdaftar di
    paket apa pun (seharusnya tidak terjadi kalau seed benar)."""

    row = (
        await db.execute(
            select(Paket.nama)
            .join(PaketFitur, PaketFitur.paket_id == Paket.id)
            .join(Fitur, Fitur.id == PaketFitur.fitur_id)
            .where(Fitur.kode == kode)
            .order_by(Paket.urutan.asc())
            .limit(1)
        )
    ).scalar_one_or_none()
    return row


async def tolak_fitur_terkunci(db: AsyncSession, kode: str) -> None:
    """Dipanggil kalau toko TIDAK punya fitur `kode` - 403 dgn body JSON
    terstruktur (lewat `detail=` HTTPException, jadi response sungguhan
    berbentuk `{"detail": {"kode":..., "fitur":..., "paket_minimal":...}}`
    - konvensi standar FastAPI, BUKAN top-level, supaya tidak perlu
    exception handler kustom yang bisa mengubah bentuk respons error di
    seluruh endpoint lain). 403 (bukan 402) - keputusan tahap ini supaya
    konsisten dgn gate hak-akses lain (role/outlet), FE beda-in alasannya
    lewat body `kode` ini, bukan lewat status code."""

    paket_minimal = await paket_minimal_untuk_fitur(db, kode)
    raise HTTPException(
        status.HTTP_403_FORBIDDEN,
        detail={"kode": "fitur_terkunci", "fitur": kode, "paket_minimal": paket_minimal},
    )


def require_fitur(kode: str):
    """Factory dependency - pakai sbg `Depends(require_fitur("qris"))` di
    router lain."""

    async def _dep(
        toko_id: uuid.UUID = Depends(get_toko_id), db: AsyncSession = Depends(get_db)
    ) -> None:
        if not await has_fitur(db, toko_id, kode):
            await tolak_fitur_terkunci(db, kode)

    return _dep
