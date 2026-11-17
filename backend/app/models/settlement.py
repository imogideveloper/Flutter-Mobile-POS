"""Settlement QRIS/e-wallet (IMOGI no. 74): dana yang diterima dari penyedia pembayaran untuk penjualan satu tanggal."""

import uuid
from datetime import date

from sqlalchemy import CheckConstraint, Date, ForeignKey, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from app.core.db import Base
from app.core.types import Money, TimestampMixin, UUIDPkMixin


class Settlement(Base, UUIDPkMixin, TimestampMixin):
    __tablename__ = "settlement"
    __table_args__ = (
        CheckConstraint("jumlah_diterima >= 0", name="ck_settlement_jumlah"),
        CheckConstraint("biaya >= 0", name="ck_settlement_biaya"),
    )

    toko_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("toko.id"))
    metode_bayar_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("metode_bayar.id"))
    tanggal: Mapped[date] = mapped_column(Date)  # tanggal PENJUALAN yang dicairkan
    jumlah_diterima: Mapped[float] = mapped_column(Money)  # bersih masuk rekening
    biaya: Mapped[float] = mapped_column(Money, default=0, server_default="0")  # MDR/potongan penyedia
    referensi: Mapped[str | None] = mapped_column(String(100), nullable=True)
    catatan: Mapped[str | None] = mapped_column(Text, nullable=True)
