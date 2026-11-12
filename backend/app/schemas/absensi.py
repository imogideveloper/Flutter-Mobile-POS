import uuid
from datetime import date, datetime

from pydantic import BaseModel, Field


class AbsensiMasukIn(BaseModel):
    outlet_id: uuid.UUID | None = None
    catatan: str | None = Field(default=None, max_length=300)


class AbsensiKeluarIn(BaseModel):
    catatan: str | None = Field(default=None, max_length=300)


class AbsensiOut(BaseModel):
    id: uuid.UUID
    pengguna_id: uuid.UUID
    pengguna_nama: str
    outlet_id: uuid.UUID
    jam_masuk: datetime
    jam_keluar: datetime | None
    durasi_menit: int | None  # null selama belum keluar
    status: str
    catatan: str | None


class AbsensiAktifOut(BaseModel):
    aktif: AbsensiOut | None


class RekapAbsensiKaryawanOut(BaseModel):
    pengguna_id: uuid.UUID
    pengguna_nama: str
    jumlah_hari: int
    total_menit: int
    masih_masuk: bool


class DaftarAbsensiOut(BaseModel):
    dari: date
    sampai: date
    rekap: list[RekapAbsensiKaryawanOut]
    item: list[AbsensiOut]
