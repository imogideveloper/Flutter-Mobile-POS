"""F3.F.3 - endpoint ADMIN PLATFORM (bukan owner toko), dilindungi API key
statis (app/core/admin_auth.py), BUKAN JWT/izin role toko. Setiap aktivasi
tercatat di audit_log (F3.F.3)."""

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.admin_auth import verifikasi_admin_api_key
from app.core.db import get_db
from app.schemas.langganan import AdminAktivasiLangganan
from app.services.audit_service import catat_audit
from app.services.langganan_service import admin_aktivasi_langganan

router = APIRouter(prefix="/admin/langganan", tags=["admin"], dependencies=[Depends(verifikasi_admin_api_key)])


@router.post("/aktivasi", status_code=201)
async def aktivasi(body: AdminAktivasiLangganan, db: AsyncSession = Depends(get_db)) -> dict:
    langganan = await admin_aktivasi_langganan(db, body)
    await catat_audit(
        db,
        toko_id=body.toko_id,
        pengguna_id=None,
        aksi="admin_aktivasi_langganan",
        tabel="langganan",
        record_id=langganan.id,
        data_baru={
            "paket_id": str(body.paket_id),
            "jumlah_outlet": body.jumlah_outlet,
            "periode": body.periode,
        },
    )
    await db.commit()
    return {"id": str(langganan.id), "status": langganan.status}
