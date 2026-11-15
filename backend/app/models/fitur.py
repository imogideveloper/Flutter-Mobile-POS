"""Modul 7: Fitur langganan - fitur, paket_fitur."""

import uuid

from sqlalchemy import Boolean, ForeignKey, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from app.core.db import Base
from app.core.types import CreatedAtOnlyMixin, TimestampMixin, UUIDPkMixin


class Fitur(Base, UUIDPkMixin, TimestampMixin):
    __tablename__ = "fitur"

    kode: Mapped[str] = mapped_column(String(50), unique=True)
    nama: Mapped[str] = mapped_column(String(100))
    modul: Mapped[str] = mapped_column(String(30))
    tingkat: Mapped[int] = mapped_column(Integer, default=0)  # paket minimal: 0 Gratis, 1 Pro, 2 Bisnis
    # Pelacakan pengembangan (dashboard Administrator) - diisi dari app/data/status_fitur.json
    # lewat status_fitur_service.sinkron_status_fitur; BUKAN gerbang paket.
    nomor_imogi: Mapped[int | None] = mapped_column(Integer, nullable=True)
    kunci_imogi: Mapped[str | None] = mapped_column(String(50), nullable=True)
    status_dev: Mapped[str] = mapped_column(String(15), default="belum")  # belum|sedang|sudah|tidak_relevan
    catatan_dev: Mapped[str | None] = mapped_column(Text, nullable=True)
    uji_hp: Mapped[bool] = mapped_column(Boolean, default=False)


class PaketFitur(Base, CreatedAtOnlyMixin):
    __tablename__ = "paket_fitur"

    paket_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("paket.id"), primary_key=True)
    fitur_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("fitur.id"), primary_key=True)
    batas: Mapped[int | None] = mapped_column(Integer, nullable=True)


class FiturKebutuhan(Base):
    """Klasifikasi fitur per jenis usaha F&B (inti/opsional/na) dari dokumen
    IMOGI - dibuat migrasi 0010, dipakai dashboard Administrator."""

    __tablename__ = "fitur_kebutuhan"

    fitur_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("fitur.id"), primary_key=True)
    jenis_usaha: Mapped[str] = mapped_column(String(3), primary_key=True)
    kebutuhan: Mapped[str] = mapped_column(String(8))  # inti|opsional|na
