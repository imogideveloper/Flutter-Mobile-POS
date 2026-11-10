"""Modul 3: Produk - kategori, satuan, produk, produk_varian, harga_outlet,
grup_modifier, modifier, produk_grup_modifier, resep, bundling_item,
harga_grosir."""

import uuid

from sqlalchemy import ForeignKey, Integer, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.core.db import Base
from app.core.types import CreatedAtOnlyMixin, Money, Qty, TimestampMixin, UUIDPkMixin


class Kategori(Base, UUIDPkMixin, TimestampMixin):
    __tablename__ = "kategori"

    toko_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("toko.id"))
    nama: Mapped[str] = mapped_column(String(100))
    warna: Mapped[str | None] = mapped_column(String(9), nullable=True)
    urutan: Mapped[int] = mapped_column(Integer, default=0)
    # Kategori yang masuk tiket dapur (mis. matikan untuk Minuman dingin). Bawaan: ikut tercetak.
    masuk_tiket_dapur: Mapped[bool] = mapped_column(default=True, server_default="true")
    stasiun_dapur_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("stasiun_dapur.id"), nullable=True
    )


class Satuan(Base, UUIDPkMixin, TimestampMixin):
    __tablename__ = "satuan"

    toko_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("toko.id"))
    nama: Mapped[str] = mapped_column(String(50))
    singkatan: Mapped[str] = mapped_column(String(10))


class Produk(Base, UUIDPkMixin, TimestampMixin):
    __tablename__ = "produk"
    __table_args__ = (
        UniqueConstraint("toko_id", "sku", name="uq_produk_sku"),
        UniqueConstraint("toko_id", "barcode", name="uq_produk_barcode"),
    )

    toko_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("toko.id"))
    kategori_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("kategori.id"), nullable=True)
    satuan_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("satuan.id"), nullable=True)
    sku: Mapped[str | None] = mapped_column(String(50), nullable=True)
    barcode: Mapped[str | None] = mapped_column(String(50), nullable=True)
    nama: Mapped[str] = mapped_column(String(150))
    deskripsi: Mapped[str | None] = mapped_column(Text, nullable=True)
    gambar_url: Mapped[str | None] = mapped_column(Text, nullable=True)
    tipe: Mapped[str] = mapped_column(String(20), default="barang")  # barang|jasa|bahan_baku|bundling
    lacak_stok: Mapped[bool] = mapped_column(default=True)
    punya_varian: Mapped[bool] = mapped_column(default=False)
    pakai_resep: Mapped[bool] = mapped_column(default=False)
    lacak_kedaluwarsa: Mapped[bool] = mapped_column(default=False)
    hpp: Mapped[float] = mapped_column(Money, default=0)
    harga_jual: Mapped[float] = mapped_column(Money, default=0)
    dijual: Mapped[bool] = mapped_column(default=True)
    aktif: Mapped[bool] = mapped_column(default=True)


class ProdukVarian(Base, UUIDPkMixin, TimestampMixin):
    __tablename__ = "produk_varian"

    produk_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("produk.id"))
    nama: Mapped[str] = mapped_column(String(100))
    sku: Mapped[str | None] = mapped_column(String(50), nullable=True)
    barcode: Mapped[str | None] = mapped_column(String(50), nullable=True)
    hpp: Mapped[float] = mapped_column(Money, default=0)
    harga_jual: Mapped[float] = mapped_column(Money, default=0)
    aktif: Mapped[bool] = mapped_column(default=True)


class HargaOutlet(Base, UUIDPkMixin, TimestampMixin):
    __tablename__ = "harga_outlet"
    __table_args__ = (UniqueConstraint("outlet_id", "produk_id", "varian_id"),)

    outlet_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("outlet.id"))
    produk_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("produk.id"))
    varian_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("produk_varian.id"), nullable=True)
    harga_jual: Mapped[float] = mapped_column(Money)


class GrupModifier(Base, UUIDPkMixin, TimestampMixin):
    __tablename__ = "grup_modifier"

    toko_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("toko.id"))
    nama: Mapped[str] = mapped_column(String(100))  # "Level Pedas", "Topping"
    min_pilih: Mapped[int] = mapped_column(Integer, default=0)
    maks_pilih: Mapped[int] = mapped_column(Integer, default=1)


class Modifier(Base, UUIDPkMixin, TimestampMixin):
    __tablename__ = "modifier"

    grup_modifier_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("grup_modifier.id"))
    nama: Mapped[str] = mapped_column(String(100))
    harga_tambahan: Mapped[float] = mapped_column(Money, default=0)
    urutan: Mapped[int] = mapped_column(Integer, default=0)
    aktif: Mapped[bool] = mapped_column(default=True)


class ProdukGrupModifier(Base, CreatedAtOnlyMixin):
    __tablename__ = "produk_grup_modifier"

    produk_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("produk.id"), primary_key=True)
    grup_modifier_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("grup_modifier.id"), primary_key=True)


class Resep(Base, UUIDPkMixin, TimestampMixin):
    __tablename__ = "resep"

    produk_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("produk.id"))
    varian_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("produk_varian.id"), nullable=True)
    bahan_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("produk.id"))
    qty: Mapped[float] = mapped_column(Qty)


class BundlingItem(Base, UUIDPkMixin, TimestampMixin):
    __tablename__ = "bundling_item"

    bundling_produk_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("produk.id"))
    produk_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("produk.id"))
    varian_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("produk_varian.id"), nullable=True)
    qty: Mapped[float] = mapped_column(Qty)


class HargaGrosir(Base, UUIDPkMixin, TimestampMixin):
    __tablename__ = "harga_grosir"
    __table_args__ = (UniqueConstraint("produk_id", "varian_id", "outlet_id", "min_qty"),)

    produk_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("produk.id"))
    varian_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("produk_varian.id"), nullable=True)
    outlet_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("outlet.id"), nullable=True)
    min_qty: Mapped[float] = mapped_column(Qty)
    harga: Mapped[float] = mapped_column(Money)
