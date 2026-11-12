"""Absensi karyawan (IMOGI no. 62, fitur `absensi`): jam masuk dan keluar, rekap per karyawan.

Setiap karyawan mencatat absensinya sendiri (identitas dari token). Rekap seluruh karyawan hanya
untuk peran dengan izin `laporan.lihat`. Foto dan lokasi belum dipakai.
"""

import uuid
from datetime import UTC, date, datetime, time, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_db
from app.core.deps import get_pengguna_id, get_role_id, get_toko_id
from app.models.akun import Pengguna
from app.models.ops import Absensi
from app.models.outlet import Outlet
from app.schemas.absensi import (
    AbsensiAktifOut,
    AbsensiKeluarIn,
    AbsensiMasukIn,
    AbsensiOut,
    DaftarAbsensiOut,
    RekapAbsensiKaryawanOut,
)
from app.services.fitur_service import require_fitur
from app.services.izin_service import has_izin

router = APIRouter(prefix="/absensi", tags=["absensi"], dependencies=[Depends(require_fitur("absensi"))])


def _utc(waktu: datetime) -> datetime:
    return waktu if waktu.tzinfo else waktu.replace(tzinfo=UTC)


def _menit(a: Absensi) -> int | None:
    if a.jam_keluar is None:
        return None
    return max(int((_utc(a.jam_keluar) - _utc(a.jam_masuk)).total_seconds() // 60), 0)


def _out(a: Absensi, nama: str) -> AbsensiOut:
    return AbsensiOut(
        id=a.id,
        pengguna_id=a.pengguna_id,
        pengguna_nama=nama,
        outlet_id=a.outlet_id,
        jam_masuk=a.jam_masuk,
        jam_keluar=a.jam_keluar,
        durasi_menit=_menit(a),
        status=a.status,
        catatan=a.catatan,
    )


async def _terbuka(db: AsyncSession, toko_id: uuid.UUID, pengguna_id: uuid.UUID) -> Absensi | None:
    return (
        await db.execute(
            select(Absensi)
            .where(
                Absensi.toko_id == toko_id,
                Absensi.pengguna_id == pengguna_id,
                Absensi.jam_keluar.is_(None),
                Absensi.deleted_at.is_(None),
            )
            .order_by(Absensi.jam_masuk.desc())
        )
    ).scalars().first()


async def _nama(db: AsyncSession, pengguna_id: uuid.UUID) -> str:
    pengguna = await db.get(Pengguna, pengguna_id)
    return pengguna.nama if pengguna is not None else "-"


@router.get("/saya", response_model=AbsensiAktifOut)
async def absensi_saya(
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    db: AsyncSession = Depends(get_db),
) -> AbsensiAktifOut:
    aktif = await _terbuka(db, toko_id, pengguna_id)
    return AbsensiAktifOut(aktif=_out(aktif, await _nama(db, pengguna_id)) if aktif else None)


@router.post("/masuk", response_model=AbsensiOut, status_code=status.HTTP_201_CREATED)
async def absen_masuk(
    body: AbsensiMasukIn,
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    db: AsyncSession = Depends(get_db),
) -> AbsensiOut:
    if await _terbuka(db, toko_id, pengguna_id) is not None:
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            detail={"kode": "sudah_absen_masuk", "pesan": "Anda sudah absen masuk dan belum absen keluar"},
        )
    if body.outlet_id is None:
        outlet = (
            await db.execute(select(Outlet).where(Outlet.toko_id == toko_id).order_by(Outlet.created_at))
        ).scalars().first()
    else:
        outlet = await db.get(Outlet, body.outlet_id)
    if outlet is None or outlet.toko_id != toko_id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Outlet tidak ditemukan")

    baris = Absensi(
        toko_id=toko_id,
        outlet_id=outlet.id,
        pengguna_id=pengguna_id,
        jam_masuk=datetime.now(UTC),
        status="hadir",
        catatan=body.catatan,
    )
    db.add(baris)
    await db.commit()
    await db.refresh(baris)
    return _out(baris, await _nama(db, pengguna_id))


@router.post("/keluar", response_model=AbsensiOut)
async def absen_keluar(
    body: AbsensiKeluarIn,
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    db: AsyncSession = Depends(get_db),
) -> AbsensiOut:
    baris = await _terbuka(db, toko_id, pengguna_id)
    if baris is None:
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            detail={"kode": "belum_absen_masuk", "pesan": "Belum ada absen masuk yang bisa ditutup"},
        )
    baris.jam_keluar = datetime.now(UTC)
    if body.catatan:
        baris.catatan = (f"{baris.catatan} | " if baris.catatan else "") + body.catatan
    await db.commit()
    await db.refresh(baris)
    return _out(baris, await _nama(db, pengguna_id))


@router.get("", response_model=DaftarAbsensiOut)
async def daftar_absensi(
    dari: date = Query(...),
    sampai: date = Query(...),
    # Offset zona waktu perangkat dari UTC dalam menit (WIB = 420) supaya batas hari mengikuti jam setempat.
    tz_menit: int = Query(0, ge=-840, le=840),
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> DaftarAbsensiOut:
    if sampai < dari:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Tanggal sampai lebih awal dari dari")
    lihat_semua = await has_izin(db, role_id, "laporan.lihat")
    zona = timezone(timedelta(minutes=tz_menit))
    awal = datetime.combine(dari, time.min, tzinfo=zona).astimezone(UTC)
    akhir = datetime.combine(sampai + timedelta(days=1), time.min, tzinfo=zona).astimezone(UTC)
    query = (
        select(Absensi, Pengguna.nama)
        .join(Pengguna, Pengguna.id == Absensi.pengguna_id)
        .where(
            Absensi.toko_id == toko_id,
            Absensi.deleted_at.is_(None),
            Absensi.jam_masuk >= awal,
            Absensi.jam_masuk < akhir,
        )
        .order_by(Absensi.jam_masuk.desc())
    )
    if not lihat_semua:
        query = query.where(Absensi.pengguna_id == pengguna_id)  # tanpa izin: hanya milik sendiri
    rows = (await db.execute(query)).all()

    rekap: dict[uuid.UUID, dict] = {}
    for a, nama in rows:
        r = rekap.setdefault(a.pengguna_id, {"nama": nama, "hari": set(), "menit": 0, "masih": False})
        r["hari"].add(_utc(a.jam_masuk).astimezone(zona).date())
        r["menit"] += _menit(a) or 0
        r["masih"] = r["masih"] or a.jam_keluar is None
    return DaftarAbsensiOut(
        dari=dari,
        sampai=sampai,
        rekap=sorted(
            (
                RekapAbsensiKaryawanOut(
                    pengguna_id=pid,
                    pengguna_nama=r["nama"],
                    jumlah_hari=len(r["hari"]),
                    total_menit=r["menit"],
                    masih_masuk=r["masih"],
                )
                for pid, r in rekap.items()
            ),
            key=lambda x: x.pengguna_nama.lower(),
        ),
        item=[_out(a, nama) for a, nama in rows],
    )
