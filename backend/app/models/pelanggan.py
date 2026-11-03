"""Modul 6 (pelanggan) + bagian modul 10 (loyalty): pelanggan, riwayat_poin,
level_member, aturan_poin, survei, pertanyaan_survei, jawaban_survei,
item_jawaban_survei."""

import uuid
from datetime import date, datetime

from sqlalchemy import ForeignKey, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from app.core.db import Base
from app.core.types import JSONB_PORTABLE, Money, TimestampMixin, UUIDPkMixin


class LevelMember(Base, UUIDPkMixin, TimestampMixin):
    __tablename__ = "level_member"

    toko_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("toko.id"))
    nama: Mapped[str] = mapped_column(String(50))  # Silver, Gold, Platinum
    min_total_belanja: Mapped[float] = mapped_column(Money, default=0)
    diskon_persen: Mapped[float] = mapped_column(Money, default=0)
    pengali_poin: Mapped[float] = mapped_column(Money, default=1)
    urutan: Mapped[int] = mapped_column(Integer, default=0)


class Pelanggan(Base, UUIDPkMixin, TimestampMixin):
    __tablename__ = "pelanggan"

    toko_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("toko.id"))
    nama: Mapped[str] = mapped_column(String(150))
    no_hp: Mapped[str | None] = mapped_column(String(20), nullable=True)
    email: Mapped[str | None] = mapped_column(String(150), nullable=True)
    tanggal_lahir: Mapped[date | None] = mapped_column(nullable=True)
    level_member_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("level_member.id"), nullable=True)
    poin: Mapped[int] = mapped_column(Integer, default=0)
    total_belanja: Mapped[float] = mapped_column(Money, default=0)
    catatan: Mapped[str | None] = mapped_column(Text, nullable=True)
    # Opsional (tahap 3b-1) - NULL = tidak ada batas. Kalau diisi, kasbon
    # baru yang membuat total utang (sum sisa_tagihan) pelanggan ini
    # melebihi batas ditolak (lihat checkout_service.py).
    batas_kasbon: Mapped[float | None] = mapped_column(Money, nullable=True)


class AturanPoin(Base, TimestampMixin):
    __tablename__ = "aturan_poin"

    toko_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("toko.id"), primary_key=True)
    nominal_per_poin: Mapped[float] = mapped_column(Money, default=10000)
    nilai_tukar_poin: Mapped[float] = mapped_column(Money, default=100)
    min_tukar_poin: Mapped[int] = mapped_column(Integer, default=0)
    kedaluwarsa_hari: Mapped[int | None] = mapped_column(Integer, nullable=True)
    aktif: Mapped[bool] = mapped_column(default=True)


class RiwayatPoin(Base, UUIDPkMixin, TimestampMixin):
    __tablename__ = "riwayat_poin"

    pelanggan_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("pelanggan.id"))
    transaksi_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("transaksi.id"), nullable=True)
    poin: Mapped[int] = mapped_column(Integer)  # + dapat, - tukar
    keterangan: Mapped[str | None] = mapped_column(Text, nullable=True)


class Survei(Base, UUIDPkMixin, TimestampMixin):
    __tablename__ = "survei"

    toko_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("toko.id"))
    judul: Mapped[str] = mapped_column(String(150))
    tampil_di: Mapped[str] = mapped_column(String(20), default="struk")  # struk|layar_pelanggan|whatsapp
    aktif: Mapped[bool] = mapped_column(default=True)


class PertanyaanSurvei(Base, UUIDPkMixin, TimestampMixin):
    __tablename__ = "pertanyaan_survei"

    survei_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("survei.id"))
    teks: Mapped[str] = mapped_column(Text)
    tipe: Mapped[str] = mapped_column(String(20))  # rating|pilihan|teks
    opsi: Mapped[dict | None] = mapped_column(JSONB_PORTABLE, nullable=True)
    wajib: Mapped[bool] = mapped_column(default=False)
    urutan: Mapped[int] = mapped_column(Integer, default=0)


class JawabanSurvei(Base, UUIDPkMixin, TimestampMixin):
    __tablename__ = "jawaban_survei"

    survei_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("survei.id"))
    transaksi_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("transaksi.id"), nullable=True)
    pelanggan_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("pelanggan.id"), nullable=True)
    dijawab_pada: Mapped[datetime]


class ItemJawabanSurvei(Base, UUIDPkMixin, TimestampMixin):
    __tablename__ = "item_jawaban_survei"

    jawaban_survei_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("jawaban_survei.id"))
    pertanyaan_survei_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("pertanyaan_survei.id"))
    nilai_angka: Mapped[int | None] = mapped_column(Integer, nullable=True)
    nilai_teks: Mapped[str | None] = mapped_column(Text, nullable=True)
