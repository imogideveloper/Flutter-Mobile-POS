"""Deposit pelanggan (IMOGI no. 79): mutasi saldo. topup menambah, pakai dan koreksi mengurangi (liabilitas toko)."""

import uuid

from sqlalchemy import CheckConstraint, ForeignKey, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from app.core.db import Base
from app.core.types import Money, TimestampMixin, UUIDPkMixin


class DepositPelanggan(Base, UUIDPkMixin, TimestampMixin):
    __tablename__ = "deposit_pelanggan"
    __table_args__ = (
        CheckConstraint("jenis IN ('topup','pakai','koreksi')", name="ck_deposit_jenis"),
        CheckConstraint("jumlah > 0", name="ck_deposit_jumlah"),
    )

    toko_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("toko.id"))
    pelanggan_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("pelanggan.id"))
    jenis: Mapped[str] = mapped_column(String(10))
    jumlah: Mapped[float] = mapped_column(Money)
    metode_bayar_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("metode_bayar.id"), nullable=True)
    catatan: Mapped[str | None] = mapped_column(Text, nullable=True)
    dibuat_oleh: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("pengguna.id"), nullable=True)
