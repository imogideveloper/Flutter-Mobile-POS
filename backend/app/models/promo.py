"""Modul 6 (bagian pajak & promo): pajak, promo, promo_produk, promo_outlet."""

import uuid
from datetime import datetime

from sqlalchemy import Boolean, CheckConstraint, ForeignKey, Integer, Numeric, String
from sqlalchemy.orm import Mapped, mapped_column

from app.core.db import Base
from app.core.types import CreatedAtOnlyMixin, Money, TimestampMixin, UUIDPkMixin


class Pajak(Base, UUIDPkMixin, TimestampMixin):
    __tablename__ = "pajak"
    __table_args__ = (CheckConstraint("persen >= 0", name="ck_pajak_persen"),)

    toko_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("toko.id"))
    nama: Mapped[str] = mapped_column(String(50))  # PPN, PB1, Service
    tipe: Mapped[str] = mapped_column(String(20), default="pajak")  # pajak|service
    persen: Mapped[float] = mapped_column(Numeric(5, 2))
    termasuk_harga: Mapped[bool] = mapped_column(Boolean, default=False)
    urutan: Mapped[int] = mapped_column(Integer, default=0)
    aktif: Mapped[bool] = mapped_column(Boolean, default=True)


class Promo(Base, UUIDPkMixin, TimestampMixin):
    __tablename__ = "promo"
    __table_args__ = (
        CheckConstraint("tipe IN ('persen','nominal')", name="ck_promo_tipe"),
        CheckConstraint("cakupan IN ('transaksi','produk')", name="ck_promo_cakupan"),
        CheckConstraint("nilai >= 0", name="ck_promo_nilai"),
    )

    toko_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("toko.id"))
    nama: Mapped[str] = mapped_column(String(100))
    kode: Mapped[str | None] = mapped_column(String(30), nullable=True)
    tipe: Mapped[str] = mapped_column(String(20))  # persen|nominal
    nilai: Mapped[float] = mapped_column(Money)
    cakupan: Mapped[str] = mapped_column(String(20), default="transaksi")  # transaksi|produk
    min_belanja: Mapped[float] = mapped_column(Money, default=0)
    maks_diskon: Mapped[float | None] = mapped_column(Money, nullable=True)
    berlaku_mulai: Mapped[datetime | None] = mapped_column(nullable=True)
    berlaku_sampai: Mapped[datetime | None] = mapped_column(nullable=True)
    aktif: Mapped[bool] = mapped_column(Boolean, default=True)
    # Promo ulang tahun (IMOGI no. 56): hanya bisa dipakai untuk pelanggan yang berulang tahun hari ini.
    khusus_ulang_tahun: Mapped[bool] = mapped_column(Boolean, default=False, server_default="false")


class PromoProduk(Base, CreatedAtOnlyMixin):
    __tablename__ = "promo_produk"

    promo_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("promo.id"), primary_key=True)
    produk_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("produk.id"), primary_key=True)


class PromoOutlet(Base, CreatedAtOnlyMixin):
    __tablename__ = "promo_outlet"

    promo_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("promo.id"), primary_key=True)
    outlet_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("outlet.id"), primary_key=True)
