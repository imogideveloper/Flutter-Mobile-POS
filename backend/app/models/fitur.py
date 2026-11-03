"""Modul 7: Fitur langganan - fitur, paket_fitur."""

import uuid

from sqlalchemy import ForeignKey, Integer, String
from sqlalchemy.orm import Mapped, mapped_column

from app.core.db import Base
from app.core.types import CreatedAtOnlyMixin, TimestampMixin, UUIDPkMixin


class Fitur(Base, UUIDPkMixin, TimestampMixin):
    __tablename__ = "fitur"

    kode: Mapped[str] = mapped_column(String(50), unique=True)
    nama: Mapped[str] = mapped_column(String(100))
    modul: Mapped[str] = mapped_column(String(30))
    tingkat: Mapped[int] = mapped_column(Integer, default=0)  # paket minimal: 0 Gratis, 1 Pro, 2 Bisnis


class PaketFitur(Base, CreatedAtOnlyMixin):
    __tablename__ = "paket_fitur"

    paket_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("paket.id"), primary_key=True)
    fitur_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("fitur.id"), primary_key=True)
    batas: Mapped[int | None] = mapped_column(Integer, nullable=True)
