"""Modul 9: Tipe pesanan, meja, dapur - tipe_order, tipe_order_pajak,
produk_pajak, meja, stasiun_dapur, pesanan_dapur, item_pesanan_dapur,
antrean_harian."""

import uuid
from datetime import date, datetime

from sqlalchemy import (
    Boolean,
    CheckConstraint,
    DateTime,
    ForeignKey,
    Integer,
    Numeric,
    String,
    UniqueConstraint,
    func,
)
from sqlalchemy.orm import Mapped, mapped_column

from app.core.db import Base
from app.core.types import CreatedAtOnlyMixin, TimestampMixin, UUIDPkMixin


class TipeOrder(Base, UUIDPkMixin, TimestampMixin):
    __tablename__ = "tipe_order"
    __table_args__ = (
        CheckConstraint(
            "kanal IN ('makan_di_tempat','bawa_pulang','antar','online','langsung')",
            name="ck_tipe_order_kanal",
        ),
    )

    toko_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("toko.id"))
    nama: Mapped[str] = mapped_column(String(50))
    kanal: Mapped[str] = mapped_column(String(20), default="langsung")
    pakai_meja: Mapped[bool] = mapped_column(Boolean, default=False)
    markup_persen: Mapped[float] = mapped_column(Numeric(5, 2), default=0)
    urutan: Mapped[int] = mapped_column(Integer, default=0)
    aktif: Mapped[bool] = mapped_column(Boolean, default=True)


class TipeOrderPajak(Base, CreatedAtOnlyMixin):
    __tablename__ = "tipe_order_pajak"

    tipe_order_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("tipe_order.id"), primary_key=True)
    pajak_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("pajak.id"), primary_key=True)


class ProdukPajak(Base, CreatedAtOnlyMixin):
    __tablename__ = "produk_pajak"

    produk_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("produk.id"), primary_key=True)
    pajak_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("pajak.id"), primary_key=True)


class Meja(Base, UUIDPkMixin, TimestampMixin):
    __tablename__ = "meja"
    __table_args__ = (UniqueConstraint("outlet_id", "nama"),)

    outlet_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("outlet.id"))
    nama: Mapped[str] = mapped_column(String(30))
    area: Mapped[str | None] = mapped_column(String(50), nullable=True)
    kapasitas: Mapped[int | None] = mapped_column(Integer, nullable=True)
    urutan: Mapped[int] = mapped_column(Integer, default=0)
    aktif: Mapped[bool] = mapped_column(Boolean, default=True)


class StasiunDapur(Base, UUIDPkMixin, TimestampMixin):
    __tablename__ = "stasiun_dapur"
    __table_args__ = (CheckConstraint("lebar_kertas_mm IN (58,80)", name="ck_stasiun_dapur_lebar"),)

    outlet_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("outlet.id"))
    nama: Mapped[str] = mapped_column(String(50))
    printer_alamat: Mapped[str | None] = mapped_column(String(100), nullable=True)
    lebar_kertas_mm: Mapped[int] = mapped_column(Integer, default=58)
    aktif: Mapped[bool] = mapped_column(Boolean, default=True)


class PesananDapur(Base, UUIDPkMixin, TimestampMixin):
    __tablename__ = "pesanan_dapur"
    __table_args__ = (
        CheckConstraint(
            "status IN ('baru','dimasak','siap','disajikan','dibatalkan')",
            name="ck_pesanan_dapur_status",
        ),
    )

    transaksi_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("transaksi.id"))
    stasiun_dapur_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("stasiun_dapur.id"), nullable=True)
    urutan_kirim: Mapped[int] = mapped_column(Integer, default=1)
    status: Mapped[str] = mapped_column(String(20), default="baru")
    dicetak_pada: Mapped[datetime | None] = mapped_column(nullable=True)
    siap_pada: Mapped[datetime | None] = mapped_column(nullable=True)


class ItemPesananDapur(Base, UUIDPkMixin, TimestampMixin):
    __tablename__ = "item_pesanan_dapur"
    __table_args__ = (CheckConstraint("qty > 0", name="ck_item_pesanan_dapur_qty"),)

    pesanan_dapur_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("pesanan_dapur.id"))
    item_transaksi_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("item_transaksi.id"))
    qty: Mapped[float] = mapped_column(Numeric(14, 4))


class AntreanHarian(Base):
    """Hanya created_at/updated_at (TANPA deleted_at) - lihat DDL asli; PK
    komposit, bukan UUID tunggal."""

    __tablename__ = "antrean_harian"

    outlet_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("outlet.id"), primary_key=True)
    perangkat_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("perangkat.id"), primary_key=True)
    tanggal: Mapped[date] = mapped_column(primary_key=True)
    prefix: Mapped[str] = mapped_column(String(3), default="")
    nomor_terakhir: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )
