"""Pengaturan tingkat platform (bukan per toko) - mis. lama masa trial
berdasarkan usia akun. Dikelola admin Imogi (lewat endpoint admin, nanti
dashboard admin), dibaca backend saat menentukan paket efektif toko."""

from datetime import datetime

from sqlalchemy import DateTime, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column

from app.core.db import Base


class PengaturanPlatform(Base):
    __tablename__ = "pengaturan_platform"

    kunci: Mapped[str] = mapped_column(String(50), primary_key=True)
    nilai: Mapped[str] = mapped_column(Text)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )
