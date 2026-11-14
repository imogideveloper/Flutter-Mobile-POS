"""Jadwal shift mingguan dan pengajuan cuti/sakit/izin (IMOGI no. 63)."""

import uuid
from datetime import date, datetime

from sqlalchemy import CheckConstraint, Date, DateTime, ForeignKey, Integer, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.core.db import Base
from app.core.types import TimestampMixin, UUIDPkMixin

SHIFT_JADWAL = ("libur", "pagi", "siang")
JENIS_CUTI = ("cuti", "sakit", "izin")
STATUS_CUTI = ("menunggu", "disetujui", "ditolak", "dibatalkan")


class JadwalKerja(Base, UUIDPkMixin, TimestampMixin):
    """Pola mingguan satu karyawan: satu baris per hari (1 = Senin ... 7 = Minggu)."""

    __tablename__ = "jadwal_kerja"
    __table_args__ = (
        UniqueConstraint("pengguna_id", "hari", name="uq_jadwal_kerja_pengguna_hari"),
        CheckConstraint("hari BETWEEN 1 AND 7", name="ck_jadwal_kerja_hari"),
        CheckConstraint("shift IN ('libur','pagi','siang')", name="ck_jadwal_kerja_shift"),
    )

    toko_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("toko.id"))
    pengguna_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("pengguna.id"))
    hari: Mapped[int] = mapped_column(Integer)
    shift: Mapped[str] = mapped_column(String(10))
    # "HH:MM" waktu setempat toko; kosong bila libur.
    jam_mulai: Mapped[str | None] = mapped_column(String(5), nullable=True)
    jam_selesai: Mapped[str | None] = mapped_column(String(5), nullable=True)


class PengajuanCuti(Base, UUIDPkMixin, TimestampMixin):
    __tablename__ = "pengajuan_cuti"
    __table_args__ = (
        CheckConstraint("jenis IN ('cuti','sakit','izin')", name="ck_pengajuan_cuti_jenis"),
        CheckConstraint("status IN ('menunggu','disetujui','ditolak','dibatalkan')", name="ck_pengajuan_cuti_status"),
        CheckConstraint("tanggal_selesai >= tanggal_mulai", name="ck_pengajuan_cuti_tanggal"),
    )

    toko_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("toko.id"))
    pengguna_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("pengguna.id"))
    jenis: Mapped[str] = mapped_column(String(10))
    tanggal_mulai: Mapped[date] = mapped_column(Date)
    tanggal_selesai: Mapped[date] = mapped_column(Date)
    alasan: Mapped[str | None] = mapped_column(Text, nullable=True)
    status: Mapped[str] = mapped_column(String(12), default="menunggu")
    diputuskan_oleh: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("pengguna.id"), nullable=True)
    diputuskan_pada: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    catatan_keputusan: Mapped[str | None] = mapped_column(Text, nullable=True)
