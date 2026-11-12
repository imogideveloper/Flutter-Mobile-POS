"""Unggah pelanggan massal via template (IMOGI no. 53, fitur `customer_import`, paket Professional).

Klien mengurai CSV lalu mengirim baris-barisnya. Tiap baris berdiri sendiri: baris yang salah atau
nomor HP-nya sudah terdaftar ditolak dengan alasan, baris lain tetap masuk. `simulasi=true` hanya
memeriksa tanpa menyimpan.
"""

import re
import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_db
from app.core.deps import get_pengguna_id, get_role_id, get_toko_id
from app.models.pelanggan import Pelanggan
from app.schemas.pelanggan_impor import HasilBarisPelangganOut, ImporPelangganIn, ImporPelangganOut
from app.services.audit_service import catat_audit
from app.services.fitur_service import require_fitur
from app.services.izin_service import has_izin

router = APIRouter(tags=["pelanggan"], dependencies=[Depends(require_fitur("customer_import"))])

_EMAIL = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


def _bersih(teks: str | None) -> str | None:
    teks = (teks or "").strip()
    return teks or None


def bersihkan_hp(teks: str | None) -> str | None:
    """Sisakan angka (tanda + di depan, spasi, strip, kurung dibuang). Kosong -> None."""
    digit = re.sub(r"\D", "", teks or "")
    return digit or None


def kunci_hp(digit: str) -> str:
    """Bentuk pembanding: 0812..., 62812..., dan +62812... dianggap nomor yang sama."""
    if digit.startswith("62"):
        return digit
    if digit.startswith("0"):
        return "62" + digit[1:]
    return "62" + digit


@router.post("/pelanggan/impor", response_model=ImporPelangganOut)
async def impor_pelanggan(
    body: ImporPelangganIn,
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> ImporPelangganOut:
    if not await has_izin(db, role_id, "pelanggan.kelola"):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Role ini tidak punya izin pelanggan.kelola")

    ada = (
        await db.execute(select(Pelanggan.no_hp).where(Pelanggan.toko_id == toko_id, Pelanggan.deleted_at.is_(None)))
    ).scalars().all()
    hp_dipakai = {kunci_hp(d) for d in (bersihkan_hp(h) for h in ada) if d}

    hasil: list[HasilBarisPelangganOut] = []
    diterima = 0
    for nomor, baris in enumerate(body.baris, start=1):
        nama = baris.nama.strip()

        def tolak(pesan: str) -> None:
            hasil.append(HasilBarisPelangganOut(nomor=nomor, nama=nama, status="ditolak", pesan=pesan))

        if not nama:
            tolak("Nama pelanggan wajib diisi")
            continue
        hp = bersihkan_hp(baris.no_hp)
        if hp is not None and not 9 <= len(hp) <= 15:
            tolak(f"Nomor HP {baris.no_hp} tidak valid (9 sampai 15 angka)")
            continue
        email = _bersih(baris.email)
        if email is not None and not _EMAIL.match(email):
            tolak(f"Email {email} tidak valid")
            continue
        if hp is not None and kunci_hp(hp) in hp_dipakai:
            tolak(f"Nomor HP {hp} sudah terdaftar")
            continue

        if hp is not None:
            hp_dipakai.add(kunci_hp(hp))
        if not body.simulasi:
            db.add(
                Pelanggan(
                    toko_id=toko_id,
                    nama=nama,
                    no_hp=hp,
                    email=email,
                    tanggal_lahir=baris.tanggal_lahir,
                    catatan=_bersih(baris.catatan),
                )
            )
        diterima += 1
        hasil.append(HasilBarisPelangganOut(nomor=nomor, nama=nama, status="diterima"))

    if not body.simulasi and diterima:
        await db.flush()
        await catat_audit(
            db, toko_id=toko_id, pengguna_id=pengguna_id, aksi="impor_pelanggan",
            tabel="pelanggan", record_id=None, data_baru={"diterima": diterima, "total_baris": len(body.baris)},
        )
        await db.commit()

    return ImporPelangganOut(
        simulasi=body.simulasi, diterima=diterima, ditolak=len(body.baris) - diterima, hasil=hasil
    )
