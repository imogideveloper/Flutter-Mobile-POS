"""Pengaturan tingkat platform (bukan per toko) - mis. lama masa trial
berdasarkan usia akun. Dikelola admin Imogi (lewat endpoint admin, nanti
dashboard admin), dibaca backend saat menentukan paket efektif toko."""

from datetime import datetime

from sqlalchemy import Boolean, DateTime, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column

from app.core.db import Base
from app.core.types import TimestampMixin, UUIDPkMixin


class PengaturanPlatform(Base):
    __tablename__ = "pengaturan_platform"

    kunci: Mapped[str] = mapped_column(String(50), primary_key=True)
    nilai: Mapped[str] = mapped_column(Text)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )


class AkunAdmin(Base, UUIDPkMixin, TimestampMixin):
    """Akun Administrator Imogi (lintas toko) - login email+password,
    terpisah dari pengguna/karyawan toko. Dipakai dashboard admin."""

    __tablename__ = "akun_admin"

    email: Mapped[str] = mapped_column(String(150), unique=True)
    nama: Mapped[str] = mapped_column(String(100))
    password_hash: Mapped[str] = mapped_column(String(100))
    aktif: Mapped[bool] = mapped_column(Boolean, default=True)
    terakhir_login: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
