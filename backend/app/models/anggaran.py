"""Anggaran bulanan (IMOGI no. 82): batas biaya per kategori pengeluaran untuk satu bulan."""

import uuid
from datetime import date

from sqlalchemy import CheckConstraint, Date, ForeignKey, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.core.db import Base
from app.core.types import Money, TimestampMixin, UUIDPkMixin


class Anggaran(Base, UUIDPkMixin, TimestampMixin):
    __tablename__ = "anggaran"
    __table_args__ = (
        UniqueConstraint("toko_id", "bulan", "kategori", name="uq_anggaran_toko_bulan_kategori"),
        CheckConstraint("jumlah >= 0", name="ck_anggaran_jumlah"),
    )

    toko_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("toko.id"))
    bulan: Mapped[date] = mapped_column(Date)  # selalu tanggal 1
    kategori: Mapped[str] = mapped_column(String(30))
    jumlah: Mapped[float] = mapped_column(Money)
