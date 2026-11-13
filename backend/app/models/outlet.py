"""Modul 1: Bisnis & tenant - paket, toko, langganan, outlet,
pengaturan_outlet, perangkat."""

import uuid
from datetime import datetime

from sqlalchemy import ForeignKey, Integer, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.db import Base
from app.core.types import JSONB_PORTABLE, Money, TimestampMixin, UUIDPkMixin


class Paket(Base, UUIDPkMixin, TimestampMixin):
    __tablename__ = "paket"

    nama: Mapped[str] = mapped_column(String(50))
    urutan: Mapped[int] = mapped_column(Integer, default=0)  # 0 Gratis, 1 Pro, 2 Bisnis
    harga_bulanan: Mapped[float] = mapped_column(Money, default=0)
    harga_tahunan: Mapped[float | None] = mapped_column(Money, nullable=True)
    maks_outlet: Mapped[int | None] = mapped_column(Integer, nullable=True)
    maks_pengguna: Mapped[int | None] = mapped_column(Integer, nullable=True)
    maks_produk: Mapped[int | None] = mapped_column(Integer, nullable=True)
    aktif: Mapped[bool] = mapped_column(default=True)


class Toko(Base, UUIDPkMixin, TimestampMixin):
    __tablename__ = "toko"

    nama: Mapped[str] = mapped_column(String(150))
    jenis_usaha: Mapped[str | None] = mapped_column(String(50), nullable=True)
    pemilik_nama: Mapped[str | None] = mapped_column(String(150), nullable=True)
    email: Mapped[str | None] = mapped_column(String(150), nullable=True)
    no_hp: Mapped[str | None] = mapped_column(String(20), nullable=True)
    alamat: Mapped[str | None] = mapped_column(Text, nullable=True)
    logo_url: Mapped[str | None] = mapped_column(Text, nullable=True)
    zona_waktu: Mapped[str] = mapped_column(String(50), default="Asia/Jakarta")
    mata_uang: Mapped[str] = mapped_column(String(3), default="IDR")
    pengaturan_fitur: Mapped[dict] = mapped_column(JSONB_PORTABLE, default=dict)


class Langganan(Base, UUIDPkMixin, TimestampMixin):
    __tablename__ = "langganan"

    toko_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("toko.id"))
    paket_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("paket.id"))
    jumlah_outlet: Mapped[int] = mapped_column(Integer, default=1)
    periode: Mapped[str] = mapped_column(String(10), default="bulanan")  # bulanan|tahunan
    mulai: Mapped[datetime]
    berakhir: Mapped[datetime | None] = mapped_column(nullable=True)
    status: Mapped[str] = mapped_column(String(20), default="aktif")  # trial|aktif|kedaluwarsa|batal
    jumlah_bayar: Mapped[float] = mapped_column(Money, default=0)
    ref_pembayaran: Mapped[str | None] = mapped_column(String(100), nullable=True)


class PermintaanUpgrade(Base, UUIDPkMixin, TimestampMixin):
    """Asalnya F3.F.2 murni catatan minat manual (TIDAK ada pembayaran di
    app) - DIBALIK atas permintaan eksplisit: sekarang baris ini juga
    jadi tiket pembayaran Xendit. 'baru' = invoice dibuat/menunggu bayar,
    'selesai' = sudah dibayar & langganan sudah diaktifkan otomatis
    (lihat services/xendit_service.py), 'batal' = invoice kedaluwarsa/
    dibatalkan Xendit. 'dihubungi' dipertahankan utk request lama yang
    masih diproses manual (jalur admin/aktivasi manual TETAP ada,
    lihat routers/admin_langganan.py, utk kasus di luar Xendit mis.
    transfer bank manual)."""

    __tablename__ = "permintaan_upgrade"

    toko_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("toko.id"))
    paket_tujuan_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("paket.id"))
    jumlah_outlet: Mapped[int] = mapped_column(Integer, default=1)
    periode: Mapped[str] = mapped_column(String(10), default="bulanan")  # bulanan|tahunan
    status: Mapped[str] = mapped_column(String(20), default="baru")  # baru|dihubungi|selesai|batal
    catatan: Mapped[str | None] = mapped_column(Text, nullable=True)
    xendit_invoice_id: Mapped[str | None] = mapped_column(String(100), nullable=True)
    invoice_url: Mapped[str | None] = mapped_column(Text, nullable=True)
    jumlah_bayar: Mapped[float | None] = mapped_column(Money, nullable=True)
    # Jalur BARU (QRIS/VA langsung di app, tanpa redirect browser) - lewat
    # Xendit Payment Requests API (/v3/payment_requests), beda dari
    # Invoice API lama di atas. metode_bayar = 'qris'|'<bank>_virtual_account'
    # (snake_case dari channel_code Xendit), detail_bayar = qr_string ATAU
    # account_number mentah dari Xendit (dipakai lagi kalau user minta
    # tampilkan ulang tanpa bikin payment request baru).
    xendit_payment_request_id: Mapped[str | None] = mapped_column(String(100), nullable=True)
    metode_bayar: Mapped[str | None] = mapped_column(String(30), nullable=True)
    detail_bayar: Mapped[dict | None] = mapped_column(JSONB_PORTABLE, nullable=True)


class Outlet(Base, UUIDPkMixin, TimestampMixin):
    __tablename__ = "outlet"
    __table_args__ = (UniqueConstraint("toko_id", "kode"),)

    toko_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("toko.id"))
    kode: Mapped[str] = mapped_column(String(20))
    nama: Mapped[str] = mapped_column(String(150))
    alamat: Mapped[str | None] = mapped_column(Text, nullable=True)
    no_hp: Mapped[str | None] = mapped_column(String(20), nullable=True)
    aktif: Mapped[bool] = mapped_column(default=True)

    pengaturan: Mapped["PengaturanOutlet | None"] = relationship(back_populates="outlet", uselist=False)


class PengaturanOutlet(Base, TimestampMixin):
    __tablename__ = "pengaturan_outlet"

    outlet_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("outlet.id"), primary_key=True)
    header_struk: Mapped[str | None] = mapped_column(Text, nullable=True)
    footer_struk: Mapped[str | None] = mapped_column(Text, nullable=True)
    tampil_logo: Mapped[bool] = mapped_column(default=True)
    lebar_kertas_mm: Mapped[int] = mapped_column(Integer, default=58)  # 58|80
    pembulatan: Mapped[int] = mapped_column(Integer, default=0)
    izinkan_stok_minus: Mapped[bool] = mapped_column(default=True)
    wajib_buka_shift: Mapped[bool] = mapped_column(default=True)
    struk_ringkas: Mapped[bool] = mapped_column(default=False)
    pakai_nomor_antrean: Mapped[bool] = mapped_column(default=False)
    # Pengaturan nomor antrian (IMOGI no. 34): awalan ("A" -> A-001) dan angka awal tiap hari.
    antrean_awalan: Mapped[str] = mapped_column(String(5), default="A", server_default="A")
    antrean_mulai: Mapped[int] = mapped_column(Integer, default=1, server_default="1")
    # Estimasi selesai pesanan (IMOGI no. 26): lama pengerjaan bawaan dalam menit; 0 = tidak dipakai.
    estimasi_menit: Mapped[int] = mapped_column(Integer, default=0, server_default="0")
    # Batas margin (%) produk: margin di bawah ini ditandai rendah (IMOGI no. 37); bawaan 50 untuk F&B.
    batas_margin: Mapped[int] = mapped_column(Integer, default=50, server_default="50")

    outlet: Mapped["Outlet"] = relationship(back_populates="pengaturan")


class Perangkat(Base, UUIDPkMixin, TimestampMixin):
    __tablename__ = "perangkat"
    __table_args__ = (UniqueConstraint("toko_id", "device_uid"),)

    toko_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("toko.id"))
    outlet_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("outlet.id"), nullable=True)
    nama: Mapped[str] = mapped_column(String(100))
    device_uid: Mapped[str] = mapped_column(String(150))
    platform: Mapped[str | None] = mapped_column(String(20), nullable=True)
    versi_app: Mapped[str | None] = mapped_column(String(20), nullable=True)
    fcm_token: Mapped[str | None] = mapped_column(Text, nullable=True)
    terakhir_sync: Mapped[datetime | None] = mapped_column(nullable=True)
    aktif: Mapped[bool] = mapped_column(default=True)
