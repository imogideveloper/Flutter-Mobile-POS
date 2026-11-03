"""Modul 10 (bagian karyawan): absensi."""

import uuid
from datetime import datetime

from sqlalchemy import CheckConstraint, ForeignKey, Numeric, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from app.core.db import Base
from app.core.types import TimestampMixin, UUIDPkMixin


class Absensi(Base, UUIDPkMixin, TimestampMixin):
    __tablename__ = "absensi"
    __table_args__ = (
        CheckConstraint(
            "status IN ('hadir','terlambat','izin','sakit','alpa')", name="ck_absensi_status"
        ),
    )

    toko_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("toko.id"))
    outlet_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("outlet.id"))
    pengguna_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("pengguna.id"))
    perangkat_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("perangkat.id"), nullable=True)
    jam_masuk: Mapped[datetime]
    jam_keluar: Mapped[datetime | None] = mapped_column(nullable=True)
    foto_masuk_url: Mapped[str | None] = mapped_column(Text, nullable=True)
    foto_keluar_url: Mapped[str | None] = mapped_column(Text, nullable=True)
    lat_masuk: Mapped[float | None] = mapped_column(Numeric(9, 6), nullable=True)
    lng_masuk: Mapped[float | None] = mapped_column(Numeric(9, 6), nullable=True)
    status: Mapped[str] = mapped_column(String(20), default="hadir")
    catatan: Mapped[str | None] = mapped_column(Text, nullable=True)
