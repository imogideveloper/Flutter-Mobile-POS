"""Aset tetap (IMOGI no. 83): peralatan usaha yang disusutkan garis lurus per bulan."""

import uuid
from datetime import date

from sqlalchemy import CheckConstraint, Date, ForeignKey, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from app.core.db import Base
from app.core.types import Money, TimestampMixin, UUIDPkMixin


class AsetTetap(Base, UUIDPkMixin, TimestampMixin):
    __tablename__ = "aset_tetap"
    __table_args__ = (
        CheckConstraint("harga_perolehan > 0", name="ck_aset_harga"),
        CheckConstraint("nilai_residu >= 0", name="ck_aset_residu"),
        CheckConstraint("umur_bulan > 0", name="ck_aset_umur"),
    )

    toko_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("toko.id"))
    nama: Mapped[str] = mapped_column(String(150))
    tanggal_perolehan: Mapped[date] = mapped_column(Date)
    harga_perolehan: Mapped[float] = mapped_column(Money)
    nilai_residu: Mapped[float] = mapped_column(Money, default=0, server_default="0")
    umur_bulan: Mapped[int] = mapped_column(Integer)
    catatan: Mapped[str | None] = mapped_column(Text, nullable=True)
