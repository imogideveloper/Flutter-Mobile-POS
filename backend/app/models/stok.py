"""Modul 4: Stok & pembelian - stok, mutasi_stok, supplier, pembelian,
item_pembelian, stok_opname, item_opname, transfer_stok, item_transfer,
batch_stok."""

import uuid
from datetime import date, datetime

from sqlalchemy import CheckConstraint, ForeignKey, Integer, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.core.db import Base
from app.core.types import Money, Qty, TimestampMixin, UUIDPkMixin


class Stok(Base, UUIDPkMixin, TimestampMixin):
    __tablename__ = "stok"
    __table_args__ = (UniqueConstraint("outlet_id", "produk_id", "varian_id"),)

    outlet_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("outlet.id"))
    produk_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("produk.id"))
    varian_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("produk_varian.id"), nullable=True)
    jumlah: Mapped[float] = mapped_column(Qty, default=0)
    batas_minimum: Mapped[float] = mapped_column(Qty, default=0)
    hpp_rata_rata: Mapped[float] = mapped_column(Money, default=0)


class MutasiStok(Base, UUIDPkMixin, TimestampMixin):
    __tablename__ = "mutasi_stok"

    toko_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("toko.id"))
    outlet_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("outlet.id"))
    produk_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("produk.id"))
    varian_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("produk_varian.id"), nullable=True)
    batch_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("batch_stok.id"), nullable=True)
    jenis: Mapped[str] = mapped_column(String(20))
    qty: Mapped[float] = mapped_column(Qty)  # + masuk, - keluar
    hpp_satuan: Mapped[float] = mapped_column(Money, default=0)
    saldo_setelah: Mapped[float | None] = mapped_column(Qty, nullable=True)
    ref_tipe: Mapped[str | None] = mapped_column(String(30), nullable=True)
    ref_id: Mapped[uuid.UUID | None] = mapped_column(nullable=True)
    catatan: Mapped[str | None] = mapped_column(Text, nullable=True)
    dibuat_oleh: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("pengguna.id"), nullable=True)

    __table_args__ = (
        CheckConstraint(
            "jenis IN ('stok_awal','pembelian','penjualan','refund','void',"
            "'opname','transfer_masuk','transfer_keluar','penyesuaian','produksi')",
            name="ck_mutasi_stok_jenis",
        ),
    )


class Supplier(Base, UUIDPkMixin, TimestampMixin):
    __tablename__ = "supplier"

    toko_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("toko.id"))
    nama: Mapped[str] = mapped_column(String(150))
    kontak: Mapped[str | None] = mapped_column(String(150), nullable=True)
    no_hp: Mapped[str | None] = mapped_column(String(20), nullable=True)
    email: Mapped[str | None] = mapped_column(String(150), nullable=True)
    alamat: Mapped[str | None] = mapped_column(Text, nullable=True)


class Pembelian(Base, UUIDPkMixin, TimestampMixin):
    __tablename__ = "pembelian"
    __table_args__ = (UniqueConstraint("toko_id", "nomor"),)

    toko_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("toko.id"))
    outlet_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("outlet.id"))
    supplier_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("supplier.id"), nullable=True)
    nomor: Mapped[str] = mapped_column(String(50))
    tanggal: Mapped[date]
    status: Mapped[str] = mapped_column(String(20), default="draft")  # draft|dipesan|diterima|batal
    subtotal: Mapped[float] = mapped_column(Money, default=0)
    diskon: Mapped[float] = mapped_column(Money, default=0)
    pajak: Mapped[float] = mapped_column(Money, default=0)
    total: Mapped[float] = mapped_column(Money, default=0)
    status_bayar: Mapped[str] = mapped_column(String(20), default="belum")  # belum|sebagian|lunas
    catatan: Mapped[str | None] = mapped_column(Text, nullable=True)
    dibuat_oleh: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("pengguna.id"), nullable=True)


class ItemPembelian(Base, UUIDPkMixin, TimestampMixin):
    __tablename__ = "item_pembelian"

    pembelian_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("pembelian.id"))
    produk_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("produk.id"))
    varian_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("produk_varian.id"), nullable=True)
    qty: Mapped[float] = mapped_column(Qty)
    harga_satuan: Mapped[float] = mapped_column(Money, default=0)
    subtotal: Mapped[float] = mapped_column(Money, default=0)


class StokOpname(Base, UUIDPkMixin, TimestampMixin):
    __tablename__ = "stok_opname"
    __table_args__ = (UniqueConstraint("outlet_id", "nomor"),)

    outlet_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("outlet.id"))
    nomor: Mapped[str] = mapped_column(String(50))
    tanggal: Mapped[date]
    status: Mapped[str] = mapped_column(String(20), default="draft")  # draft|selesai|batal
    catatan: Mapped[str | None] = mapped_column(Text, nullable=True)
    dibuat_oleh: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("pengguna.id"), nullable=True)
    disetujui_oleh: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("pengguna.id"), nullable=True)


class ItemOpname(Base, UUIDPkMixin, TimestampMixin):
    __tablename__ = "item_opname"

    stok_opname_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("stok_opname.id"))
    produk_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("produk.id"))
    varian_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("produk_varian.id"), nullable=True)
    qty_sistem: Mapped[float] = mapped_column(Qty)
    qty_fisik: Mapped[float] = mapped_column(Qty)
    # selisih = qty_fisik - qty_sistem (GENERATED STORED di Postgres, lihat migration 0001).
    # Dihitung di application layer saat INSERT/UPDATE agar SQLite test tetap konsisten.
    selisih: Mapped[float] = mapped_column(Qty)
    catatan: Mapped[str | None] = mapped_column(Text, nullable=True)


class TransferStok(Base, UUIDPkMixin, TimestampMixin):
    __tablename__ = "transfer_stok"
    __table_args__ = (
        UniqueConstraint("toko_id", "nomor"),
        CheckConstraint("dari_outlet_id <> ke_outlet_id", name="ck_transfer_stok_outlet_beda"),
    )

    toko_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("toko.id"))
    dari_outlet_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("outlet.id"))
    ke_outlet_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("outlet.id"))
    nomor: Mapped[str] = mapped_column(String(50))
    status: Mapped[str] = mapped_column(String(20), default="draft")  # draft|dikirim|diterima|batal
    dikirim_pada: Mapped[datetime | None] = mapped_column(nullable=True)
    diterima_pada: Mapped[datetime | None] = mapped_column(nullable=True)
    dibuat_oleh: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("pengguna.id"), nullable=True)


class ItemTransfer(Base, UUIDPkMixin, TimestampMixin):
    __tablename__ = "item_transfer"

    transfer_stok_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("transfer_stok.id"))
    produk_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("produk.id"))
    varian_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("produk_varian.id"), nullable=True)
    qty: Mapped[float] = mapped_column(Qty)


class BatchStok(Base, UUIDPkMixin, TimestampMixin):
    __tablename__ = "batch_stok"

    outlet_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("outlet.id"))
    produk_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("produk.id"))
    varian_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("produk_varian.id"), nullable=True)
    pembelian_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("pembelian.id"), nullable=True)
    nomor_batch: Mapped[str | None] = mapped_column(String(50), nullable=True)
    tanggal_kedaluwarsa: Mapped[date]
    qty_awal: Mapped[float] = mapped_column(Qty)
    qty_sisa: Mapped[float] = mapped_column(Qty)
    ingatkan_hari: Mapped[int] = mapped_column(Integer, default=30)
