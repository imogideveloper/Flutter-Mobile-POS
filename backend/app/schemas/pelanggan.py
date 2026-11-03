import uuid
from datetime import datetime
from decimal import Decimal

from pydantic import BaseModel


class PelangganIn(BaseModel):
    nama: str
    no_hp: str | None = None
    email: str | None = None
    catatan: str | None = None
    # Opsional (tahap 3b-1) - lihat Pelanggan.batas_kasbon.
    batas_kasbon: Decimal | None = None
    level_member_id: uuid.UUID | None = None


class PelangganUpdateIn(BaseModel):
    """Tahap 5 - semua field opsional (partial update via
    `model_dump(exclude_unset=True)`, sama pola dgn PenggunaUpdateIn)."""

    nama: str | None = None
    no_hp: str | None = None
    email: str | None = None
    catatan: str | None = None
    batas_kasbon: Decimal | None = None
    level_member_id: uuid.UUID | None = None


class PelangganOut(BaseModel):
    id: uuid.UUID
    toko_id: uuid.UUID
    nama: str
    no_hp: str | None
    email: str | None
    poin: int
    total_belanja: Decimal
    catatan: str | None
    batas_kasbon: Decimal | None
    level_member_id: uuid.UUID | None = None

    model_config = {"from_attributes": True}


class LevelMemberIn(BaseModel):
    nama: str
    min_total_belanja: Decimal = Decimal("0")
    diskon_persen: Decimal = Decimal("0")
    pengali_poin: Decimal = Decimal("1")
    urutan: int = 0


class LevelMemberUpdateIn(BaseModel):
    nama: str | None = None
    min_total_belanja: Decimal | None = None
    diskon_persen: Decimal | None = None
    pengali_poin: Decimal | None = None
    urutan: int | None = None


class LevelMemberOut(BaseModel):
    id: uuid.UUID
    toko_id: uuid.UUID
    nama: str
    min_total_belanja: Decimal
    diskon_persen: Decimal
    pengali_poin: Decimal
    urutan: int

    model_config = {"from_attributes": True}


class AturanPoinIn(BaseModel):
    nominal_per_poin: Decimal = Decimal("10000")
    nilai_tukar_poin: Decimal = Decimal("100")
    min_tukar_poin: int = 0
    kedaluwarsa_hari: int | None = None
    aktif: bool = True


class AturanPoinUpdateIn(BaseModel):
    nominal_per_poin: Decimal | None = None
    nilai_tukar_poin: Decimal | None = None
    min_tukar_poin: int | None = None
    kedaluwarsa_hari: int | None = None
    aktif: bool | None = None


class AturanPoinOut(BaseModel):
    toko_id: uuid.UUID
    nominal_per_poin: Decimal
    nilai_tukar_poin: Decimal
    min_tukar_poin: int
    kedaluwarsa_hari: int | None
    aktif: bool

    model_config = {"from_attributes": True}


class RiwayatPoinOut(BaseModel):
    id: uuid.UUID
    pelanggan_id: uuid.UUID
    transaksi_id: uuid.UUID | None
    poin: int
    keterangan: str | None
    created_at: datetime

    model_config = {"from_attributes": True}
