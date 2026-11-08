"""Modul 5: Kasir, shift, pembayaran - shift, kas_shift, metode_bayar,
transaksi, item_transaksi, item_transaksi_modifier, transaksi_pajak,
transaksi_promo, pembayaran, refund, item_refund."""

import uuid
from datetime import date, datetime

from sqlalchemy import Boolean, CheckConstraint, ForeignKey, Integer, Numeric, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.core.db import Base
from app.core.types import JSONB_PORTABLE, Money, Qty, TimestampMixin, UUIDPkMixin


class MetodeBayar(Base, UUIDPkMixin, TimestampMixin):
    __tablename__ = "metode_bayar"
    __table_args__ = (
        CheckConstraint(
            "tipe IN ('tunai','qris','kartu','transfer','ewallet','lainnya')",
            name="ck_metode_bayar_tipe",
        ),
    )

    toko_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("toko.id"))
    nama: Mapped[str] = mapped_column(String(50))
    tipe: Mapped[str] = mapped_column(String(20))
    butuh_gateway: Mapped[bool] = mapped_column(Boolean, default=False)
    masuk_laci: Mapped[bool] = mapped_column(Boolean, default=False)
    urutan: Mapped[int] = mapped_column(Integer, default=0)
    aktif: Mapped[bool] = mapped_column(Boolean, default=True)


class Shift(Base, UUIDPkMixin, TimestampMixin):
    __tablename__ = "shift"
    __table_args__ = (CheckConstraint("status IN ('buka','tutup')", name="ck_shift_status"),)

    toko_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("toko.id"))
    outlet_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("outlet.id"))
    perangkat_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("perangkat.id"), nullable=True)
    pengguna_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("pengguna.id"))
    dibuka_pada: Mapped[datetime]
    ditutup_pada: Mapped[datetime | None] = mapped_column(nullable=True)
    modal_awal: Mapped[float] = mapped_column(Money, default=0)
    kas_seharusnya: Mapped[float | None] = mapped_column(Money, nullable=True)
    kas_aktual: Mapped[float | None] = mapped_column(Money, nullable=True)
    selisih: Mapped[float | None] = mapped_column(Money, nullable=True)
    catatan: Mapped[str | None] = mapped_column(Text, nullable=True)
    status: Mapped[str] = mapped_column(String(20), default="buka")


class KasShift(Base, UUIDPkMixin, TimestampMixin):
    __tablename__ = "kas_shift"
    __table_args__ = (
        CheckConstraint("jenis IN ('masuk','keluar')", name="ck_kas_shift_jenis"),
        CheckConstraint("jumlah > 0", name="ck_kas_shift_jumlah"),
    )

    shift_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("shift.id"))
    jenis: Mapped[str] = mapped_column(String(10))
    jumlah: Mapped[float] = mapped_column(Money)
    keterangan: Mapped[str] = mapped_column(Text)
    dibuat_oleh: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("pengguna.id"), nullable=True)


class Transaksi(Base, UUIDPkMixin, TimestampMixin):
    __tablename__ = "transaksi"
    __table_args__ = (
        UniqueConstraint("outlet_id", "nomor_struk"),
        CheckConstraint(
            "status_pesanan IS NULL OR status_pesanan IN "
            "('baru','diproses','siap','diantar','selesai','diambil','dibatalkan')",
            name="ck_transaksi_status_pesanan",
        ),
        CheckConstraint(
            "status IN ('draft','tersimpan','selesai','void','refund_sebagian','refund')",
            name="ck_transaksi_status",
        ),
        CheckConstraint(
            "status_bayar IN ('lunas','sebagian','belum_bayar')", name="ck_transaksi_status_bayar"
        ),
    )

    toko_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("toko.id"))
    outlet_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("outlet.id"))
    shift_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("shift.id"), nullable=True)
    perangkat_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("perangkat.id"), nullable=True)
    pengguna_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("pengguna.id"))
    pelanggan_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("pelanggan.id"), nullable=True)
    tipe_order_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("tipe_order.id"), nullable=True)
    meja_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("meja.id"), nullable=True)
    nomor_struk: Mapped[str] = mapped_column(String(50))
    tanggal: Mapped[datetime]
    nomor_antrean: Mapped[str | None] = mapped_column(String(10), nullable=True)
    status_pesanan: Mapped[str | None] = mapped_column(String(20), nullable=True)
    status: Mapped[str] = mapped_column(String(20), default="selesai")
    subtotal: Mapped[float] = mapped_column(Money, default=0)
    total_diskon: Mapped[float] = mapped_column(Money, default=0)
    total_pajak: Mapped[float] = mapped_column(Money, default=0)
    pembulatan: Mapped[float] = mapped_column(Money, default=0)
    total: Mapped[float] = mapped_column(Money, default=0)
    total_bayar: Mapped[float] = mapped_column(Money, default=0)
    kembalian: Mapped[float] = mapped_column(Money, default=0)
    status_bayar: Mapped[str] = mapped_column(String(20), default="lunas")
    sisa_tagihan: Mapped[float] = mapped_column(Money, default=0)
    jatuh_tempo: Mapped[date | None] = mapped_column(nullable=True)
    catatan: Mapped[str | None] = mapped_column(Text, nullable=True)
    alasan_void: Mapped[str | None] = mapped_column(Text, nullable=True)
    void_disetujui_oleh: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("pengguna.id"), nullable=True)
    disinkron_pada: Mapped[datetime | None] = mapped_column(nullable=True)
    # Temuan A.2 (tahap 5) - JSON lengkap (StrukData+PengaturanStrukData,
    # lihat lib/core/struk/struk_snapshot.dart) persis spt yang dipakai HP
    # utk cetak struk ASLI saat transaksi dibuat - disimpan apa adanya dari
    # body push (migrasi 0006), dipakai utk cetak ulang identik, TERMASUK
    # dari HP lain lewat GET /transaksi/{id} (lihat TransaksiOut).
    snapshot_struk: Mapped[dict | None] = mapped_column(JSONB_PORTABLE, nullable=True)


class ItemTransaksi(Base, UUIDPkMixin, TimestampMixin):
    __tablename__ = "item_transaksi"
    __table_args__ = (CheckConstraint("qty > 0", name="ck_item_transaksi_qty"),)

    transaksi_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("transaksi.id"))
    produk_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("produk.id"))
    varian_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("produk_varian.id"), nullable=True)
    staf_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("pengguna.id"), nullable=True)
    nama_produk: Mapped[str] = mapped_column(String(200))
    qty: Mapped[float] = mapped_column(Qty)
    harga_satuan: Mapped[float] = mapped_column(Money)
    hpp_satuan: Mapped[float] = mapped_column(Money, default=0)
    diskon: Mapped[float] = mapped_column(Money, default=0)
    subtotal: Mapped[float] = mapped_column(Money)
    catatan: Mapped[str | None] = mapped_column(Text, nullable=True)


class ItemTransaksiModifier(Base, UUIDPkMixin, TimestampMixin):
    __tablename__ = "item_transaksi_modifier"

    item_transaksi_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("item_transaksi.id"))
    modifier_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("modifier.id"), nullable=True)
    nama: Mapped[str] = mapped_column(String(100))
    harga: Mapped[float] = mapped_column(Money, default=0)


class TransaksiPajak(Base, UUIDPkMixin, TimestampMixin):
    __tablename__ = "transaksi_pajak"

    transaksi_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("transaksi.id"))
    pajak_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("pajak.id"), nullable=True)
    nama: Mapped[str] = mapped_column(String(50))
    persen: Mapped[float] = mapped_column(Numeric(5, 2))
    jumlah: Mapped[float] = mapped_column(Money)


class TransaksiPromo(Base, UUIDPkMixin, TimestampMixin):
    __tablename__ = "transaksi_promo"

    transaksi_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("transaksi.id"))
    promo_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("promo.id"), nullable=True)
    nama: Mapped[str] = mapped_column(String(100))
    jumlah_diskon: Mapped[float] = mapped_column(Money)


class Pembayaran(Base, UUIDPkMixin, TimestampMixin):
    __tablename__ = "pembayaran"
    __table_args__ = (
        CheckConstraint("jumlah > 0", name="ck_pembayaran_jumlah"),
        CheckConstraint("jenis IN ('penuh','dp','cicilan','pelunasan')", name="ck_pembayaran_jenis"),
        CheckConstraint(
            "status IN ('pending','berhasil','gagal','kedaluwarsa')", name="ck_pembayaran_status"
        ),
    )

    transaksi_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("transaksi.id"))
    metode_bayar_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("metode_bayar.id"))
    # Shift TEMPAT uang ini diterima (tahap 3b-1) - BISA beda dari
    # transaksi.shift_id utk cicilan/pelunasan kasbon yang dibayar belakangan
    # di shift lain. Nullable krn kolom ini baru (baris lama pra-migrasi
    # 0003 tidak punya nilai) - lihat shift_service.py utk cara dipakai.
    shift_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("shift.id"), nullable=True)
    jumlah: Mapped[float] = mapped_column(Money)
    jenis: Mapped[str] = mapped_column(String(20), default="penuh")
    status: Mapped[str] = mapped_column(String(20), default="berhasil")
    ref_gateway: Mapped[str | None] = mapped_column(String(150), nullable=True)
    payload_gateway: Mapped[dict | None] = mapped_column(JSONB_PORTABLE, nullable=True)
    dibayar_pada: Mapped[datetime | None] = mapped_column(nullable=True)


class Refund(Base, UUIDPkMixin, TimestampMixin):
    __tablename__ = "refund"

    transaksi_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("transaksi.id"))
    shift_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("shift.id"), nullable=True)
    metode_bayar_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("metode_bayar.id"), nullable=True)
    nomor: Mapped[str] = mapped_column(String(50))
    alasan: Mapped[str] = mapped_column(Text)
    total: Mapped[float] = mapped_column(Money)
    # Uang tunai/transfer yang BENAR2 keluar dari refund ini (tahap
    # 3b-1 aturan #5) - utk transaksi kasbon yang belum lunas, refund
    # mengurangi sisa_tagihan DULU, baru sisa lebihnya (kalau ada) yang
    # dikembalikan sbg uang. Utk refund non-kasbon ini selalu == total
    # (perilaku lama, tidak berubah). Dipakai shift_service utk rekonsiliasi
    # kas - BUKAN `total` yang murni nilai barang yang di-refund.
    kas_dikembalikan: Mapped[float] = mapped_column(Money, default=0)
    kembalikan_stok: Mapped[bool] = mapped_column(Boolean, default=True)
    dibuat_oleh: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("pengguna.id"), nullable=True)
    disetujui_oleh: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("pengguna.id"), nullable=True)


class ItemRefund(Base, UUIDPkMixin, TimestampMixin):
    __tablename__ = "item_refund"
    __table_args__ = (CheckConstraint("qty > 0", name="ck_item_refund_qty"),)

    refund_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("refund.id"))
    item_transaksi_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("item_transaksi.id"))
    qty: Mapped[float] = mapped_column(Qty)
    jumlah: Mapped[float] = mapped_column(Money)
