"""Jadwal shift mingguan dan pengajuan cuti/sakit/izin (IMOGI no. 63, fitur `staff_schedule`, Professional).

Karyawan melihat jadwalnya sendiri dan mengajukan cuti; peran dengan izin `laporan.lihat` (Owner/Manajer)
mengatur jadwal semua karyawan dan memutuskan pengajuan. Tukar jadwal belum ada.
"""

import uuid
from datetime import UTC, date, datetime, timedelta

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_db
from app.core.deps import get_pengguna_id, get_role_id, get_toko_id
from app.models.akun import Pengguna
from app.models.jadwal import JadwalKerja, PengajuanCuti
from app.schemas.jadwal import (
    CutiIn,
    CutiOut,
    HariJadwalOut,
    JadwalHariIniOut,
    JadwalKaryawanOut,
    JadwalMingguIn,
    JadwalSayaOut,
    KeputusanCutiIn,
)
from app.services.audit_service import catat_audit
from app.services.fitur_service import require_fitur
from app.services.izin_service import has_izin
from app.services.jadwal_service import cuti_disetujui_pada

router = APIRouter(tags=["jadwal"], dependencies=[Depends(require_fitur("staff_schedule"))])


async def _kelola(db: AsyncSession, role_id: uuid.UUID) -> bool:
    return await has_izin(db, role_id, "laporan.lihat")


async def _wajib_kelola(db: AsyncSession, role_id: uuid.UUID) -> None:
    if not await _kelola(db, role_id):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Tidak punya izin mengatur jadwal dan cuti")


def _hari_out(rows: list[JadwalKerja]) -> list[HariJadwalOut]:
    return [
        HariJadwalOut(hari=r.hari, shift=r.shift, jam_mulai=r.jam_mulai, jam_selesai=r.jam_selesai)
        for r in sorted(rows, key=lambda x: x.hari)
    ]


async def _baris_jadwal(db: AsyncSession, toko_id: uuid.UUID, pengguna_ids: list[uuid.UUID] | None = None):
    query = select(JadwalKerja).where(JadwalKerja.toko_id == toko_id, JadwalKerja.deleted_at.is_(None))
    if pengguna_ids is not None:
        query = query.where(JadwalKerja.pengguna_id.in_(pengguna_ids))
    return (await db.execute(query)).scalars().all()


@router.get("/jadwal", response_model=list[JadwalKaryawanOut])
async def daftar_jadwal(
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> list[JadwalKaryawanOut]:
    """Pengelola melihat semua karyawan aktif; peran lain hanya dirinya sendiri."""
    semua = await _kelola(db, role_id)
    query = select(Pengguna).where(Pengguna.toko_id == toko_id, Pengguna.deleted_at.is_(None), Pengguna.aktif.is_(True))
    if not semua:
        query = query.where(Pengguna.id == pengguna_id)
    karyawan = (await db.execute(query.order_by(Pengguna.nama))).scalars().all()
    baris = await _baris_jadwal(db, toko_id, [k.id for k in karyawan])
    per_orang: dict[uuid.UUID, list[JadwalKerja]] = {}
    for b in baris:
        per_orang.setdefault(b.pengguna_id, []).append(b)
    return [
        JadwalKaryawanOut(pengguna_id=k.id, pengguna_nama=k.nama, hari=_hari_out(per_orang.get(k.id, [])))
        for k in karyawan
    ]


@router.put("/jadwal/{pengguna_id}", response_model=JadwalKaryawanOut)
async def atur_jadwal(
    pengguna_id: uuid.UUID,
    body: JadwalMingguIn,
    toko_id: uuid.UUID = Depends(get_toko_id),
    aktor_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> JadwalKaryawanOut:
    await _wajib_kelola(db, role_id)
    karyawan = await db.get(Pengguna, pengguna_id)
    if karyawan is None or karyawan.toko_id != toko_id or karyawan.deleted_at is not None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Karyawan tidak ditemukan")

    ada = {r.hari: r for r in await _baris_jadwal(db, toko_id, [pengguna_id])}
    for h in body.hari:
        baris = ada.get(h.hari)
        if baris is None:
            baris = JadwalKerja(toko_id=toko_id, pengguna_id=pengguna_id, hari=h.hari, shift=h.shift)
            db.add(baris)
            ada[h.hari] = baris
        baris.shift = h.shift
        baris.jam_mulai = h.jam_mulai
        baris.jam_selesai = h.jam_selesai
    await catat_audit(
        db, toko_id=toko_id, pengguna_id=aktor_id, aksi="atur_jadwal", tabel="jadwal_kerja", record_id=None,
        data_baru={"karyawan": str(pengguna_id), "hari": {str(h.hari): h.shift for h in body.hari}},
    )
    await db.commit()
    return JadwalKaryawanOut(pengguna_id=karyawan.id, pengguna_nama=karyawan.nama, hari=_hari_out(list(ada.values())))


@router.get("/jadwal/saya", response_model=JadwalSayaOut)
async def jadwal_saya(
    tz_menit: int = Query(0, ge=-840, le=840),
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    db: AsyncSession = Depends(get_db),
) -> JadwalSayaOut:
    baris = await _baris_jadwal(db, toko_id, [pengguna_id])
    sekarang = (datetime.now(UTC) + timedelta(minutes=tz_menit)).replace(tzinfo=None)
    hari = sekarang.isoweekday()
    hari_ini = next((b for b in baris if b.hari == hari), None)
    cuti = await cuti_disetujui_pada(db, pengguna_id, sekarang.date())
    return JadwalSayaOut(
        hari=_hari_out(baris),
        hari_ini=JadwalHariIniOut(
            tanggal=sekarang.date(),
            hari=hari,
            shift=hari_ini.shift if hari_ini else None,
            jam_mulai=hari_ini.jam_mulai if hari_ini else None,
            jam_selesai=hari_ini.jam_selesai if hari_ini else None,
            cuti=cuti.jenis if cuti else None,
        ),
    )


# ------------------------------------------------------------------------------------------- Cuti


async def _out_cuti(db: AsyncSession, rows: list[PengajuanCuti]) -> list[CutiOut]:
    nama = {}
    if rows:
        ids = {r.pengguna_id for r in rows}
        for p in (await db.execute(select(Pengguna).where(Pengguna.id.in_(ids)))).scalars():
            nama[p.id] = p.nama
    return [
        CutiOut(
            id=r.id, pengguna_id=r.pengguna_id, pengguna_nama=nama.get(r.pengguna_id, "-"), jenis=r.jenis,
            tanggal_mulai=r.tanggal_mulai, tanggal_selesai=r.tanggal_selesai, alasan=r.alasan, status=r.status,
            diputuskan_oleh=r.diputuskan_oleh, diputuskan_pada=r.diputuskan_pada, catatan_keputusan=r.catatan_keputusan,
        )
        for r in rows
    ]


@router.post("/cuti", response_model=CutiOut, status_code=status.HTTP_201_CREATED)
async def ajukan_cuti(
    body: CutiIn,
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    db: AsyncSession = Depends(get_db),
) -> CutiOut:
    tumpang = (
        await db.execute(
            select(PengajuanCuti).where(
                PengajuanCuti.pengguna_id == pengguna_id,
                PengajuanCuti.status.in_(("menunggu", "disetujui")),
                PengajuanCuti.deleted_at.is_(None),
                PengajuanCuti.tanggal_mulai <= body.tanggal_selesai,
                PengajuanCuti.tanggal_selesai >= body.tanggal_mulai,
            )
        )
    ).scalars().first()
    if tumpang is not None:
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            detail={"kode": "cuti_tumpang_tindih", "pesan": "Sudah ada pengajuan pada tanggal yang sama"},
        )
    baris = PengajuanCuti(
        toko_id=toko_id, pengguna_id=pengguna_id, jenis=body.jenis, tanggal_mulai=body.tanggal_mulai,
        tanggal_selesai=body.tanggal_selesai, alasan=body.alasan, status="menunggu",
    )
    db.add(baris)
    await db.commit()
    await db.refresh(baris)
    return (await _out_cuti(db, [baris]))[0]


@router.get("/cuti", response_model=list[CutiOut])
async def daftar_cuti(
    status_filter: str | None = Query(None, alias="status"),
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> list[CutiOut]:
    query = select(PengajuanCuti).where(PengajuanCuti.toko_id == toko_id, PengajuanCuti.deleted_at.is_(None))
    if not await _kelola(db, role_id):
        query = query.where(PengajuanCuti.pengguna_id == pengguna_id)
    if status_filter:
        query = query.where(PengajuanCuti.status == status_filter)
    rows = (await db.execute(query.order_by(PengajuanCuti.tanggal_mulai.desc(), PengajuanCuti.created_at.desc()))).scalars().all()
    return await _out_cuti(db, list(rows))


async def _ambil_cuti(db: AsyncSession, cuti_id: uuid.UUID, toko_id: uuid.UUID) -> PengajuanCuti:
    baris = await db.get(PengajuanCuti, cuti_id)
    if baris is None or baris.toko_id != toko_id or baris.deleted_at is not None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Pengajuan tidak ditemukan")
    return baris


@router.post("/cuti/{cuti_id}/putuskan", response_model=CutiOut)
async def putuskan_cuti(
    cuti_id: uuid.UUID,
    body: KeputusanCutiIn,
    toko_id: uuid.UUID = Depends(get_toko_id),
    aktor_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> CutiOut:
    await _wajib_kelola(db, role_id)
    baris = await _ambil_cuti(db, cuti_id, toko_id)
    if baris.pengguna_id == aktor_id:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Pengajuan sendiri tidak boleh diputuskan sendiri")
    if baris.status != "menunggu":
        raise HTTPException(
            status.HTTP_409_CONFLICT, detail={"kode": "sudah_diputuskan", "pesan": f"Pengajuan sudah {baris.status}"}
        )
    baris.status = "disetujui" if body.setuju else "ditolak"
    baris.diputuskan_oleh = aktor_id
    baris.diputuskan_pada = datetime.now(UTC)
    baris.catatan_keputusan = body.catatan
    await catat_audit(
        db, toko_id=toko_id, pengguna_id=aktor_id, aksi="putuskan_cuti", tabel="pengajuan_cuti",
        record_id=baris.id, data_baru={"status": baris.status},
    )
    await db.commit()
    await db.refresh(baris)
    return (await _out_cuti(db, [baris]))[0]


@router.post("/cuti/{cuti_id}/batalkan", response_model=CutiOut)
async def batalkan_cuti(
    cuti_id: uuid.UUID,
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    db: AsyncSession = Depends(get_db),
) -> CutiOut:
    baris = await _ambil_cuti(db, cuti_id, toko_id)
    if baris.pengguna_id != pengguna_id:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Hanya pemilik pengajuan yang bisa membatalkan")
    if baris.status != "menunggu":
        raise HTTPException(
            status.HTTP_409_CONFLICT, detail={"kode": "tidak_bisa_dibatalkan", "pesan": "Hanya pengajuan yang masih menunggu yang bisa dibatalkan"}
        )
    baris.status = "dibatalkan"
    await db.commit()
    await db.refresh(baris)
    return (await _out_cuti(db, [baris]))[0]
