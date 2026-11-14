"""Jadwal kerja: pencarian jadwal per hari, cuti yang disetujui, dan penentuan terlambat (IMOGI no. 63)."""

import uuid
from datetime import date, datetime, time, timedelta

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.jadwal import JadwalKerja, PengajuanCuti

TOLERANSI_TERLAMBAT_MENIT = 10


async def jadwal_hari(db: AsyncSession, pengguna_id: uuid.UUID, hari: int) -> JadwalKerja | None:
    return (
        await db.execute(
            select(JadwalKerja).where(
                JadwalKerja.pengguna_id == pengguna_id,
                JadwalKerja.hari == hari,
                JadwalKerja.deleted_at.is_(None),
            )
        )
    ).scalar_one_or_none()


async def cuti_disetujui_pada(db: AsyncSession, pengguna_id: uuid.UUID, tanggal: date) -> PengajuanCuti | None:
    return (
        await db.execute(
            select(PengajuanCuti).where(
                PengajuanCuti.pengguna_id == pengguna_id,
                PengajuanCuti.status == "disetujui",
                PengajuanCuti.deleted_at.is_(None),
                PengajuanCuti.tanggal_mulai <= tanggal,
                PengajuanCuti.tanggal_selesai >= tanggal,
            )
        )
    ).scalars().first()


def _jam(teks: str) -> time:
    jam, menit = teks.split(":")
    return time(int(jam), int(menit))


async def status_absen_masuk(
    db: AsyncSession, *, pengguna_id: uuid.UUID, waktu_utc: datetime, tz_menit: int
) -> str:
    """'terlambat' bila masuk lewat jam mulai shift hari itu (waktu setempat) ditambah toleransi, selain
    itu 'hadir'. Tanpa jadwal, hari libur, atau jadwal tanpa jam: selalu 'hadir'."""
    lokal = (waktu_utc + timedelta(minutes=tz_menit)).replace(tzinfo=None)
    baris = await jadwal_hari(db, pengguna_id, lokal.isoweekday())
    if baris is None or baris.shift == "libur" or not baris.jam_mulai:
        return "hadir"
    batas = datetime.combine(lokal.date(), _jam(baris.jam_mulai)) + timedelta(minutes=TOLERANSI_TERLAMBAT_MENIT)
    return "terlambat" if lokal > batas else "hadir"
