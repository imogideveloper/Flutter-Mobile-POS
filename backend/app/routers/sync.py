import uuid
from datetime import datetime

from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_db
from app.core.deps import get_pengguna_id, get_role_id, get_toko_id
from app.schemas.sync import SyncPullOut, SyncPushIn, SyncPushOut
from app.services import sync_service

router = APIRouter(prefix="/sync", tags=["sync"])


@router.post("/push", response_model=SyncPushOut)
async def sync_push(
    body: SyncPushIn,
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> SyncPushOut:
    return await sync_service.push(db, toko_id=toko_id, pengguna_id=pengguna_id, role_id=role_id, body=body)


@router.get("/pull", response_model=SyncPullOut)
async def sync_pull(
    perangkat_id: uuid.UUID = Query(...),
    since: datetime = Query(..., description="Waktu sync terakhir (ISO 8601) - kosongkan sync pertama kali dgn epoch 0"),
    outlet_id: uuid.UUID | None = Query(None),
    limit: int = Query(500, ge=1, le=2000, description="Maks baris PER TABEL - lihat has_more di response"),
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> SyncPullOut:
    return await sync_service.pull(
        db, toko_id=toko_id, pengguna_id=pengguna_id, role_id=role_id,
        perangkat_id=perangkat_id, outlet_id=outlet_id, since=since, limit=limit,
    )
