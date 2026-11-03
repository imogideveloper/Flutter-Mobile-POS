import uuid
from datetime import datetime
from typing import Any

from pydantic import BaseModel


class AuditLogOut(BaseModel):
    id: uuid.UUID
    pengguna_id: uuid.UUID | None
    perangkat_id: uuid.UUID | None
    aksi: str
    tabel: str | None
    record_id: uuid.UUID | None
    data_lama: dict[str, Any] | None
    data_baru: dict[str, Any] | None
    created_at: datetime

    model_config = {"from_attributes": True}
