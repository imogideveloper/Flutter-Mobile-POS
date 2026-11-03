import uuid

from pydantic import BaseModel


class FiturOut(BaseModel):
    id: uuid.UUID
    kode: str
    nama: str
    modul: str
    tingkat: int

    model_config = {"from_attributes": True}


class FiturTokoOut(BaseModel):
    paket: str | None
    kode_fitur: list[str]
