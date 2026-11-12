"""Pengeluaran & biaya operasional (IMOGI no. 67): belanja bahan, gas, kemasan, gaji, sewa, dll."""

import uuid
from datetime import date

from sqlalchemy import CheckConstraint, Date, ForeignKey, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from app.core.db import Base
from app.core.types import Money, TimestampMixin, UUIDPkMixin

KATEGORI_PENGELUARAN = (
    "belanja_bahan",  # HPP: bahan baku
    "gas_lpg",
    "kemasan",
    "gaji",
    "sewa",
    "listrik_air",
    "pemasaran",
    "perawatan",
    "lainnya",
)


class Pengeluaran(Base, UUIDPkMixin, TimestampMixin):
    __tablename__ = "pengeluaran"
    __table_args__ = (
        CheckConstraint("jumlah > 0", name="ck_pengeluaran_jumlah"),
        CheckConstraint(
            "kategori IN ('belanja_bahan','gas_lpg','kemasan','gaji','sewa','listrik_air',"
            "'pemasaran','perawatan','lainnya')",
            name="ck_pengeluaran_kategori",
        ),
    )

    toko_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("toko.id"))
    outlet_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("outlet.id"), nullable=True)
    tanggal: Mapped[date] = mapped_column(Date)
    kategori: Mapped[str] = mapped_column(String(30))
    jumlah: Mapped[float] = mapped_column(Money)
    catatan: Mapped[str | None] = mapped_column(Text, nullable=True)
    dibuat_oleh: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("pengguna.id"), nullable=True)
