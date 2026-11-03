import uuid
from datetime import datetime
from decimal import Decimal

from pydantic import BaseModel


class BukaShiftIn(BaseModel):
    outlet_id: uuid.UUID
    modal_awal: Decimal = Decimal("0")


class TutupShiftIn(BaseModel):
    kas_aktual: Decimal


class KasShiftIn(BaseModel):
    jenis: str  # masuk|keluar
    jumlah: Decimal
    keterangan: str


class ShiftOut(BaseModel):
    id: uuid.UUID
    outlet_id: uuid.UUID
    pengguna_id: uuid.UUID
    dibuka_pada: datetime
    ditutup_pada: datetime | None
    modal_awal: Decimal
    kas_seharusnya: Decimal | None
    kas_aktual: Decimal | None
    selisih: Decimal | None
    status: str

    model_config = {"from_attributes": True}


class KasShiftOut(BaseModel):
    id: uuid.UUID
    shift_id: uuid.UUID
    jenis: str
    jumlah: Decimal
    keterangan: str

    model_config = {"from_attributes": True}
