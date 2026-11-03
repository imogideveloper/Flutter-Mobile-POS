"""Tahap 5b (desain #5) - validasi identitas karyawan yang tercatat di
operasi yang dibuat di HP (checkout, shift, kas_shift, pembatalan pesanan)
lalu di-push lewat /sync/push. Beda dari pemeriksaan izin biasa
(has_izin/require_outlet_access yang MENOLAK permintaan): operasi push
SUDAH TERJADI secara fisik di toko sebelum sempat divalidasi, jadi kalau
identitasnya ternyata tidak valid (karyawan toko lain, nonaktif, tidak
punya akses outlet, atau tidak punya izin), data TETAP disimpan apa
adanya - cuma ditandai di audit_log + notifikasi owner, TIDAK ditolak.

Endpoint online (refund, layar kelola, PIN login online) sebaliknya WAJIB
tetap menolak (403/401) seperti biasa - fungsi ini HANYA dipakai jalur
push yang datanya sudah given."""

import uuid

from fastapi import HTTPException
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.deps import require_outlet_access
from app.models.akun import Pengguna
from app.models.audit import Notifikasi
from app.services.audit_service import catat_audit
from app.services.izin_service import has_izin


async def validasi_dan_tandai(
    db: AsyncSession,
    *,
    toko_id: uuid.UUID,
    pengguna_id: uuid.UUID,
    outlet_id: uuid.UUID | None,
    kode_izin: str | None,
    operasi: str,
    tabel: str,
    record_id: uuid.UUID,
) -> None:
    alasan: list[str] = []
    pengguna = await db.get(Pengguna, pengguna_id)
    if pengguna is None or pengguna.toko_id != toko_id:
        alasan.append("pengguna_bukan_milik_toko")
    else:
        if pengguna.deleted_at is not None or not pengguna.aktif:
            alasan.append("pengguna_nonaktif")
        if outlet_id is not None:
            try:
                await require_outlet_access(
                    db, pengguna_id=pengguna_id, role_id=pengguna.role_id, outlet_id=outlet_id
                )
            except HTTPException:
                alasan.append("tidak_punya_akses_outlet")
        if kode_izin is not None and not await has_izin(db, pengguna.role_id, kode_izin):
            alasan.append("tidak_punya_izin")

    if not alasan:
        return

    await catat_audit(
        db,
        toko_id=toko_id,
        pengguna_id=pengguna_id,
        aksi="anomali_identitas",
        tabel=tabel,
        record_id=record_id,
        data_baru={"operasi": operasi, "alasan": alasan},
    )
    db.add(
        Notifikasi(
            toko_id=toko_id,
            jenis="anomali_identitas",
            judul="Data mencurigakan dari HP",
            isi=(
                f"Operasi '{operasi}' tersimpan dgn identitas karyawan yang tidak valid "
                f"({', '.join(alasan)}) - periksa audit log."
            ),
            ref_tipe=tabel,
            ref_id=record_id,
        )
    )
