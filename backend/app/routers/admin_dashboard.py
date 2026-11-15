"""Dashboard Administrator Imogi: ringkasan usaha terdaftar, paket, trial,
pengguna, dan pelacakan status pengembangan fitur - dengan filter jenis
usaha F&B (kode 3 huruf, lihat core/jenis_usaha.py). Hanya admin (login
admin atau API key)."""

from datetime import UTC, datetime, timedelta

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.admin_auth import verifikasi_admin
from app.core.db import get_db
from app.core.jenis_usaha import JENIS_USAHA_FNB
from app.models.akun import Pengguna
from app.models.fitur import Fitur, FiturKebutuhan
from app.models.outlet import Outlet, Paket, Perangkat, Toko
from app.services.fitur_service import langganan_aktif_toko, paket_efektif, trial_toko
from app.services.platform_service import (
    DEFAULT_TRIAL_NOTIFIKASI_HARI,
    KUNCI_TRIAL_NOTIFIKASI_HARI,
    ambil_int,
)

router = APIRouter(prefix="/admin/dashboard", tags=["admin"], dependencies=[Depends(verifikasi_admin)])


def _cek_jenis(jenis_usaha: str | None) -> str | None:
    if jenis_usaha is None or jenis_usaha == "":
        return None
    kode = jenis_usaha.strip().upper()
    if kode not in JENIS_USAHA_FNB:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, f"Jenis usaha tidak dikenal: {jenis_usaha}")
    return kode


def _utc(dt: datetime) -> datetime:
    return dt if dt.tzinfo is not None else dt.replace(tzinfo=UTC)


class ItemJumlah(BaseModel):
    kode: str
    nama: str
    jumlah: int


class RingkasanFitur(BaseModel):
    sudah: int
    sedang: int
    belum: int
    tidak_relevan: int
    uji_hp: int
    total: int


class RingkasanTrial(BaseModel):
    aktif_diatur: bool
    durasi_bulan: int
    usaha_dalam_trial: int
    usaha_trial_berakhir: int
    usaha_hampir_berakhir: int
    batas_notifikasi_hari: int


class RingkasanOut(BaseModel):
    jenis_usaha: str | None
    total_usaha: int
    usaha_baru_30_hari: int
    total_pengguna: int
    per_paket: list[ItemJumlah]
    per_jenis_usaha: list[ItemJumlah]
    trial: RingkasanTrial
    fitur: RingkasanFitur


class UsahaOut(BaseModel):
    id: str
    nama: str
    jenis_usaha: str | None
    jenis_usaha_nama: str | None
    pemilik_nama: str | None
    email: str | None
    no_hp: str | None
    terdaftar: datetime
    usia_hari: int
    paket: str
    paket_langganan: str
    status_langganan: str
    trial_aktif: bool | None
    trial_berakhir: datetime | None
    trial_hari_tersisa: int | None
    jumlah_pengguna: int
    jumlah_outlet: int
    terakhir_sync: datetime | None


class FiturOut(BaseModel):
    nomor: int
    kode: str
    nama: str
    modul: str
    paket_minimal: int
    status: str  # status efektif utk filter (tidak_relevan bila 'na' di jenis usaha terpilih)
    status_dev: str
    kebutuhan: str | None  # inti|opsional|na bila ada filter jenis usaha
    uji_hp: bool
    catatan: str | None


async def _toko_terfilter(db: AsyncSession, jenis: str | None) -> list[Toko]:
    q = select(Toko).where(Toko.deleted_at.is_(None))
    if jenis is not None:
        q = q.where(Toko.jenis_usaha == jenis)
    return list((await db.execute(q.order_by(Toko.created_at.desc()))).scalars().all())


async def _jumlah_pengguna(db: AsyncSession, toko_id) -> int:
    return (
        await db.execute(
            select(func.count())
            .select_from(Pengguna)
            .where(Pengguna.toko_id == toko_id, Pengguna.deleted_at.is_(None), Pengguna.aktif.is_(True))
        )
    ).scalar_one()


async def _fitur_efektif(db: AsyncSession, jenis: str | None) -> list[FiturOut]:
    fitur_rows = (
        await db.execute(select(Fitur).where(Fitur.nomor_imogi.is_not(None)).order_by(Fitur.nomor_imogi))
    ).scalars().all()
    kebutuhan: dict = {}
    if jenis is not None:
        kebutuhan = {
            r.fitur_id: r.kebutuhan
            for r in (
                await db.execute(select(FiturKebutuhan).where(FiturKebutuhan.jenis_usaha == jenis))
            ).scalars().all()
        }
    hasil: list[FiturOut] = []
    for f in fitur_rows:
        butuh = kebutuhan.get(f.id) if jenis is not None else None
        efektif = "tidak_relevan" if butuh == "na" else f.status_dev
        hasil.append(
            FiturOut(
                nomor=f.nomor_imogi,
                kode=f.kode,
                nama=f.nama,
                modul=f.modul,
                paket_minimal=f.tingkat,
                status=efektif,
                status_dev=f.status_dev,
                kebutuhan=butuh,
                uji_hp=f.uji_hp,
                catatan=f.catatan_dev,
            )
        )
    return hasil


@router.get("/jenis-usaha", response_model=list[ItemJumlah])
async def daftar_jenis_usaha() -> list[ItemJumlah]:
    """Tujuh jenis usaha F&B untuk filter dashboard (jumlah = 0, hanya pilihan)."""
    return [ItemJumlah(kode=k, nama=n, jumlah=0) for k, n in JENIS_USAHA_FNB.items()]


@router.get("/fitur", response_model=list[FiturOut])
async def daftar_fitur(
    jenis_usaha: str | None = Query(default=None), db: AsyncSession = Depends(get_db)
) -> list[FiturOut]:
    return await _fitur_efektif(db, _cek_jenis(jenis_usaha))


@router.get("/usaha", response_model=list[UsahaOut])
async def daftar_usaha(
    jenis_usaha: str | None = Query(default=None),
    q: str | None = Query(default=None, description="cari nama usaha/pemilik/email"),
    db: AsyncSession = Depends(get_db),
) -> list[UsahaOut]:
    jenis = _cek_jenis(jenis_usaha)
    sekarang = datetime.now(UTC)
    hasil: list[UsahaOut] = []
    for toko in await _toko_terfilter(db, jenis):
        if q:
            kunci = q.strip().lower()
            if not any(kunci in (v or "").lower() for v in (toko.nama, toko.pemilik_nama, toko.email)):
                continue
        efektif = await paket_efektif(db, toko.id)
        langganan = await langganan_aktif_toko(db, toko.id)
        paket_langganan = await db.get(Paket, langganan.paket_id) if langganan else None
        trial = await trial_toko(db, toko.id)
        jumlah_outlet = (
            await db.execute(select(func.count()).select_from(Outlet).where(Outlet.toko_id == toko.id))
        ).scalar_one()
        terakhir_sync = (
            await db.execute(select(func.max(Perangkat.terakhir_sync)).where(Perangkat.toko_id == toko.id))
        ).scalar_one()
        hasil.append(
            UsahaOut(
                id=str(toko.id),
                nama=toko.nama,
                jenis_usaha=toko.jenis_usaha,
                jenis_usaha_nama=JENIS_USAHA_FNB.get(toko.jenis_usaha or ""),
                pemilik_nama=toko.pemilik_nama,
                email=toko.email,
                no_hp=toko.no_hp,
                terdaftar=toko.created_at,
                usia_hari=max(0, (sekarang - _utc(toko.created_at)).days),
                paket=efektif.nama,
                paket_langganan=paket_langganan.nama if paket_langganan else "Gratis",
                status_langganan=langganan.status if langganan else "gratis",
                trial_aktif=trial.aktif if trial else None,
                trial_berakhir=trial.berakhir if trial else None,
                trial_hari_tersisa=trial.hari_tersisa if trial else None,
                jumlah_pengguna=await _jumlah_pengguna(db, toko.id),
                jumlah_outlet=jumlah_outlet,
                terakhir_sync=terakhir_sync,
            )
        )
    return hasil


@router.get("/ringkasan", response_model=RingkasanOut)
async def ringkasan(
    jenis_usaha: str | None = Query(default=None), db: AsyncSession = Depends(get_db)
) -> RingkasanOut:
    jenis = _cek_jenis(jenis_usaha)
    sekarang = datetime.now(UTC)
    batas_notif = await ambil_int(db, KUNCI_TRIAL_NOTIFIKASI_HARI, DEFAULT_TRIAL_NOTIFIKASI_HARI)
    toko_list = await _toko_terfilter(db, jenis)

    per_paket: dict[str, int] = {}
    per_jenis: dict[str, int] = {}
    dalam_trial = berakhir = hampir = 0
    durasi = 0
    pengguna_total = 0
    for toko in toko_list:
        efektif = await paket_efektif(db, toko.id)
        per_paket[efektif.nama] = per_paket.get(efektif.nama, 0) + 1
        kode_jenis = toko.jenis_usaha or "-"
        per_jenis[kode_jenis] = per_jenis.get(kode_jenis, 0) + 1
        trial = await trial_toko(db, toko.id)
        if trial is not None:
            durasi = trial.durasi_bulan
            if trial.aktif:
                dalam_trial += 1
                if trial.hari_tersisa <= batas_notif:
                    hampir += 1
            else:
                berakhir += 1
        pengguna_total += await _jumlah_pengguna(db, toko.id)

    baru = sum(1 for t in toko_list if _utc(t.created_at) >= sekarang - timedelta(days=30))
    fitur = await _fitur_efektif(db, jenis)
    hitung = {s: sum(1 for f in fitur if f.status == s) for s in ("sudah", "sedang", "belum", "tidak_relevan")}

    return RingkasanOut(
        jenis_usaha=jenis,
        total_usaha=len(toko_list),
        usaha_baru_30_hari=baru,
        total_pengguna=pengguna_total,
        per_paket=[ItemJumlah(kode=n, nama=n, jumlah=j) for n, j in sorted(per_paket.items())],
        per_jenis_usaha=[
            ItemJumlah(kode=k, nama=JENIS_USAHA_FNB.get(k, k), jumlah=j) for k, j in sorted(per_jenis.items())
        ],
        trial=RingkasanTrial(
            aktif_diatur=durasi > 0,
            durasi_bulan=durasi,
            usaha_dalam_trial=dalam_trial,
            usaha_trial_berakhir=berakhir,
            usaha_hampir_berakhir=hampir,
            batas_notifikasi_hari=batas_notif,
        ),
        fitur=RingkasanFitur(**hitung, uji_hp=sum(1 for f in fitur if f.uji_hp), total=len(fitur)),
    )
