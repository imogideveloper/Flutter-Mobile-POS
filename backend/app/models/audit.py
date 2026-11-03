"""Modul teknis: sync_log, audit_log, notifikasi."""

import uuid
from datetime import datetime

from sqlalchemy import CheckConstraint, ForeignKey, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from app.core.db import Base
from app.core.types import CreatedAtOnlyMixin, Inet, JSONB_PORTABLE, TimestampMixin, UUIDPkMixin


class SyncLog(Base, UUIDPkMixin, TimestampMixin):
    __tablename__ = "sync_log"
    __table_args__ = (
        CheckConstraint("arah IN ('push','pull')", name="ck_sync_log_arah"),
        CheckConstraint(
            "status IN ('berjalan','berhasil','gagal','sebagian')", name="ck_sync_log_status"
        ),
    )

    toko_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("toko.id"))
    perangkat_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("perangkat.id"))
    arah: Mapped[str] = mapped_column(String(10))
    mulai: Mapped[datetime]
    selesai: Mapped[datetime | None] = mapped_column(nullable=True)
    jumlah_record: Mapped[int] = mapped_column(Integer, default=0)
    status: Mapped[str] = mapped_column(String(20), default="berjalan")
    pesan_error: Mapped[str | None] = mapped_column(Text, nullable=True)


class AuditLog(Base, UUIDPkMixin, CreatedAtOnlyMixin):
    __tablename__ = "audit_log"

    toko_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("toko.id"), nullable=True)
    pengguna_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("pengguna.id"), nullable=True)
    perangkat_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("perangkat.id"), nullable=True)
    aksi: Mapped[str] = mapped_column(String(30))  # create, update, delete, void, login, approve
    tabel: Mapped[str | None] = mapped_column(String(50), nullable=True)
    record_id: Mapped[uuid.UUID | None] = mapped_column(nullable=True)
    data_lama: Mapped[dict | None] = mapped_column(JSONB_PORTABLE, nullable=True)
    data_baru: Mapped[dict | None] = mapped_column(JSONB_PORTABLE, nullable=True)
    # Migration 0001 (DDL resmi) mendeklarasikan kolom ini `inet` asli di
    # Postgres - WAJIB tipe native (lihat types.py::Inet), BUKAN varchar
    # biasa. asyncpg menolak bind VARCHAR ke kolom inet sungguhan
    # (DatatypeMismatchError) - celah ini sempat lolos pytest krn SQLite
    # test tidak pernah memvalidasi tipe sampai sedetail ini.
    ip_address: Mapped[str | None] = mapped_column(Inet, nullable=True)


class Notifikasi(Base, UUIDPkMixin, TimestampMixin):
    __tablename__ = "notifikasi"

    toko_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("toko.id"))
    pengguna_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("pengguna.id"), nullable=True)
    jenis: Mapped[str] = mapped_column(String(30))  # stok_menipis, selisih_kas, langganan
    judul: Mapped[str] = mapped_column(String(150))
    isi: Mapped[str | None] = mapped_column(Text, nullable=True)
    ref_tipe: Mapped[str | None] = mapped_column(String(30), nullable=True)
    ref_id: Mapped[uuid.UUID | None] = mapped_column(nullable=True)
    dibaca_pada: Mapped[datetime | None] = mapped_column(nullable=True)
