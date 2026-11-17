"""Tutup buku (IMOGI no. 78): semua pencatatan pembukuan sampai tanggal [sampai] dikunci."""

import uuid
from datetime import date

from sqlalchemy import Date, ForeignKey, Text
from sqlalchemy.orm import Mapped, mapped_column

from app.core.db import Base
from app.core.types import TimestampMixin, UUIDPkMixin


class TutupBuku(Base, UUIDPkMixin, TimestampMixin):
    __tablename__ = "tutup_buku"

    toko_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("toko.id"))
    sampai: Mapped[date] = mapped_column(Date)
    ditutup_oleh: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("pengguna.id"), nullable=True)
    catatan: Mapped[str | None] = mapped_column(Text, nullable=True)
