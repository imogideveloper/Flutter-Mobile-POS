import uuid

from pydantic import BaseModel


class PenggunaIn(BaseModel):
    role_id: uuid.UUID
    nama: str
    email: str | None = None
    no_hp: str | None = None
    pin: str | None = None
    outlet_ids: list[uuid.UUID] = []


class PenggunaUpdateIn(BaseModel):
    role_id: uuid.UUID | None = None
    nama: str | None = None
    email: str | None = None
    no_hp: str | None = None
    aktif: bool | None = None
    # Tahap 5 B.2 - None = tidak diubah; list (termasuk kosong) = replace-all
    # akses outlet pengguna ini, sama pola dgn PUT .../grup-modifier.
    outlet_ids: list[uuid.UUID] | None = None


class ResetPinIn(BaseModel):
    pin: str


class PenggunaOut(BaseModel):
    id: uuid.UUID
    toko_id: uuid.UUID
    role_id: uuid.UUID
    nama: str
    email: str | None
    no_hp: str | None
    aktif: bool
    outlet_ids: list[uuid.UUID] = []

    model_config = {"from_attributes": True}


class RoleOut(BaseModel):
    id: uuid.UUID
    nama: str
    is_system: bool

    model_config = {"from_attributes": True}
