"""Modul 2: Pengguna & hak akses - role, izin, role_izin, pengguna,
akses_outlet."""

import uuid
from datetime import datetime

from sqlalchemy import ForeignKey, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from app.core.db import Base
from app.core.types import CreatedAtOnlyMixin, TimestampMixin, UUIDPkMixin


class Role(Base, UUIDPkMixin, TimestampMixin):
    __tablename__ = "role"

    toko_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("toko.id"), nullable=True)  # NULL = bawaan sistem
    nama: Mapped[str] = mapped_column(String(50))
    is_system: Mapped[bool] = mapped_column(default=False)


class Izin(Base, UUIDPkMixin, TimestampMixin):
    __tablename__ = "izin"

    kode: Mapped[str] = mapped_column(String(60), unique=True)  # mis. transaksi.void
    modul: Mapped[str] = mapped_column(String(30))
    deskripsi: Mapped[str | None] = mapped_column(Text, nullable=True)


class RoleIzin(Base, CreatedAtOnlyMixin):
    __tablename__ = "role_izin"

    role_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("role.id"), primary_key=True)
    izin_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("izin.id"), primary_key=True)


class Pengguna(Base, UUIDPkMixin, TimestampMixin):
    __tablename__ = "pengguna"

    toko_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("toko.id"))
    role_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("role.id"))
    nama: Mapped[str] = mapped_column(String(150))
    email: Mapped[str | None] = mapped_column(String(150), nullable=True)
    no_hp: Mapped[str | None] = mapped_column(String(20), nullable=True)
    password_hash: Mapped[str | None] = mapped_column(Text, nullable=True)
    pin_hash: Mapped[str | None] = mapped_column(Text, nullable=True)
    aktif: Mapped[bool] = mapped_column(default=True)
    terakhir_login: Mapped[datetime | None] = mapped_column(nullable=True)


class AksesOutlet(Base, CreatedAtOnlyMixin):
    __tablename__ = "akses_outlet"

    pengguna_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("pengguna.id"), primary_key=True)
    outlet_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("outlet.id"), primary_key=True)
