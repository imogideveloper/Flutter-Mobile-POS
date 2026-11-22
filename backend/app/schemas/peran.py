import uuid

from pydantic import BaseModel, Field


class IzinOut(BaseModel):
    kode: str
    modul: str
    deskripsi: str | None = None

    model_config = {"from_attributes": True}


class PeranDetailOut(BaseModel):
    id: uuid.UUID
    nama: str
    is_system: bool
    izin_kode: list[str]
    jumlah_pengguna: int


class PeranIn(BaseModel):
    nama: str = Field(min_length=1, max_length=50)
    izin_kode: list[str] = []


class PeranUbahIn(BaseModel):
    nama: str | None = Field(default=None, min_length=1, max_length=50)
    izin_kode: list[str] | None = None
