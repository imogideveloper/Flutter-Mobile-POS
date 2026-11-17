"""Survei pelanggan (IMOGI no. 59): pemilik membuat survei (pertanyaan rating/pilihan/teks), kasir mengisikan
jawaban pelanggan, pemilik melihat hasil (rata-rata rating, sebaran pilihan, komentar terbaru)."""

import uuid
from datetime import UTC, datetime

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_db
from app.core.deps import get_role_id, get_toko_id
from app.models.pelanggan import ItemJawabanSurvei, JawabanSurvei, Pelanggan, PertanyaanSurvei, Survei
from app.models.transaksi import Transaksi
from app.services.fitur_service import require_fitur
from app.services.izin_service import has_izin

router = APIRouter(prefix="/survei", tags=["survei"], dependencies=[Depends(require_fitur("survei"))])

_TIPE = ("rating", "pilihan", "teks")
_TAMPIL = ("struk", "layar_pelanggan", "whatsapp")
_RATING_MIN, _RATING_MAX = 1, 5


class PertanyaanIn(BaseModel):
    teks: str = Field(min_length=1, max_length=300)
    tipe: str
    opsi: list[str] | None = None
    wajib: bool = False


class SurveiIn(BaseModel):
    judul: str = Field(min_length=1, max_length=150)
    tampil_di: str = "struk"
    pertanyaan: list[PertanyaanIn] = Field(min_length=1, max_length=20)


class SurveiUpdateIn(BaseModel):
    judul: str | None = Field(default=None, min_length=1, max_length=150)
    aktif: bool | None = None


class PertanyaanOut(BaseModel):
    id: uuid.UUID
    teks: str
    tipe: str
    opsi: list[str] | None
    wajib: bool
    urutan: int


class SurveiOut(BaseModel):
    id: uuid.UUID
    judul: str
    tampil_di: str
    aktif: bool
    pertanyaan: list[PertanyaanOut]


class JawabanItemIn(BaseModel):
    pertanyaan_id: uuid.UUID
    nilai_angka: int | None = None
    nilai_teks: str | None = Field(default=None, max_length=1000)


class JawabanIn(BaseModel):
    transaksi_id: uuid.UUID | None = None
    pelanggan_id: uuid.UUID | None = None
    jawaban: list[JawabanItemIn] = Field(min_length=1, max_length=20)


class HasilPertanyaanOut(BaseModel):
    pertanyaan_id: uuid.UUID
    teks: str
    tipe: str
    jumlah_jawaban: int
    rata_rata: float | None = None
    sebaran: dict[str, int] = {}
    komentar: list[str] = []


class HasilSurveiOut(BaseModel):
    survei_id: uuid.UUID
    judul: str
    jumlah_responden: int
    pertanyaan: list[HasilPertanyaanOut]


async def _wajib_izin(db: AsyncSession, role_id: uuid.UUID, kode: str) -> None:
    if not await has_izin(db, role_id, kode):
        raise HTTPException(status.HTTP_403_FORBIDDEN, f"Role ini tidak punya izin {kode}")


async def _survei_milik_toko(db: AsyncSession, survei_id: uuid.UUID, toko_id: uuid.UUID) -> Survei:
    survei = await db.get(Survei, survei_id)
    if survei is None or survei.toko_id != toko_id or survei.deleted_at is not None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Survei tidak ditemukan")
    return survei


async def _pertanyaan_survei(db: AsyncSession, survei_id: uuid.UUID) -> list[PertanyaanSurvei]:
    return list(
        (
            await db.execute(
                select(PertanyaanSurvei)
                .where(PertanyaanSurvei.survei_id == survei_id, PertanyaanSurvei.deleted_at.is_(None))
                .order_by(PertanyaanSurvei.urutan)
            )
        ).scalars()
    )


def _keluaran(survei: Survei, pertanyaan: list[PertanyaanSurvei]) -> SurveiOut:
    return SurveiOut(
        id=survei.id,
        judul=survei.judul,
        tampil_di=survei.tampil_di,
        aktif=survei.aktif,
        pertanyaan=[
            PertanyaanOut(id=p.id, teks=p.teks, tipe=p.tipe, opsi=p.opsi, wajib=p.wajib, urutan=p.urutan)
            for p in pertanyaan
        ],
    )


@router.get("", response_model=list[SurveiOut])
async def daftar_survei(
    toko_id: uuid.UUID = Depends(get_toko_id), db: AsyncSession = Depends(get_db)
) -> list[SurveiOut]:
    rows = (
        await db.execute(
            select(Survei).where(Survei.toko_id == toko_id, Survei.deleted_at.is_(None)).order_by(Survei.created_at)
        )
    ).scalars().all()
    return [_keluaran(s, await _pertanyaan_survei(db, s.id)) for s in rows]


@router.post("", response_model=SurveiOut, status_code=status.HTTP_201_CREATED)
async def buat_survei(
    body: SurveiIn,
    toko_id: uuid.UUID = Depends(get_toko_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> SurveiOut:
    await _wajib_izin(db, role_id, "pelanggan.kelola")
    if body.tampil_di not in _TAMPIL:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, "tampil_di tidak dikenal")
    survei = Survei(toko_id=toko_id, judul=body.judul.strip(), tampil_di=body.tampil_di)
    db.add(survei)
    await db.flush()
    daftar: list[PertanyaanSurvei] = []
    for urutan, q in enumerate(body.pertanyaan):
        if q.tipe not in _TIPE:
            raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, f"Tipe pertanyaan {q.tipe} tidak dikenal")
        opsi = [o.strip() for o in (q.opsi or []) if o.strip()]
        if q.tipe == "pilihan" and len(opsi) < 2:
            raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, "Pertanyaan pilihan butuh minimal 2 opsi")
        p = PertanyaanSurvei(
            survei_id=survei.id,
            teks=q.teks.strip(),
            tipe=q.tipe,
            opsi=opsi if q.tipe == "pilihan" else None,
            wajib=q.wajib,
            urutan=urutan,
        )
        db.add(p)
        daftar.append(p)
    await db.commit()
    await db.refresh(survei)
    for p in daftar:
        await db.refresh(p)
    return _keluaran(survei, daftar)


@router.patch("/{survei_id}", response_model=SurveiOut)
async def ubah_survei(
    survei_id: uuid.UUID,
    body: SurveiUpdateIn,
    toko_id: uuid.UUID = Depends(get_toko_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> SurveiOut:
    await _wajib_izin(db, role_id, "pelanggan.kelola")
    survei = await _survei_milik_toko(db, survei_id, toko_id)
    if body.judul is not None:
        survei.judul = body.judul.strip()
    if body.aktif is not None:
        survei.aktif = body.aktif
    await db.commit()
    await db.refresh(survei)
    return _keluaran(survei, await _pertanyaan_survei(db, survei.id))


@router.delete("/{survei_id}", status_code=status.HTTP_204_NO_CONTENT)
async def hapus_survei(
    survei_id: uuid.UUID,
    toko_id: uuid.UUID = Depends(get_toko_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> None:
    await _wajib_izin(db, role_id, "pelanggan.kelola")
    survei = await _survei_milik_toko(db, survei_id, toko_id)
    survei.deleted_at = datetime.now(UTC)
    await db.commit()


@router.post("/{survei_id}/jawaban", status_code=status.HTTP_201_CREATED)
async def kirim_jawaban(
    survei_id: uuid.UUID,
    body: JawabanIn,
    toko_id: uuid.UUID = Depends(get_toko_id),
    db: AsyncSession = Depends(get_db),
) -> dict:
    survei = await _survei_milik_toko(db, survei_id, toko_id)
    if not survei.aktif:
        raise HTTPException(status.HTTP_409_CONFLICT, "Survei ini sedang tidak aktif")
    if body.pelanggan_id is not None:
        pel = await db.get(Pelanggan, body.pelanggan_id)
        if pel is None or pel.toko_id != toko_id:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Pelanggan tidak ditemukan")
    if body.transaksi_id is not None:
        trx = await db.get(Transaksi, body.transaksi_id)
        if trx is None or trx.toko_id != toko_id:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Transaksi tidak ditemukan")

    pertanyaan = {p.id: p for p in await _pertanyaan_survei(db, survei.id)}
    diisi: dict[uuid.UUID, JawabanItemIn] = {}
    for j in body.jawaban:
        if j.pertanyaan_id not in pertanyaan:
            raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, "Pertanyaan bukan bagian dari survei ini")
        p = pertanyaan[j.pertanyaan_id]
        if p.tipe == "rating":
            if j.nilai_angka is None or not _RATING_MIN <= j.nilai_angka <= _RATING_MAX:
                raise HTTPException(
                    status.HTTP_422_UNPROCESSABLE_CONTENT, f"Rating harus {_RATING_MIN}-{_RATING_MAX}"
                )
        elif p.tipe == "pilihan":
            if j.nilai_teks not in (p.opsi or []):
                raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, "Jawaban bukan salah satu opsi")
        elif not (j.nilai_teks or "").strip():
            continue
        diisi[j.pertanyaan_id] = j
    for pid, p in pertanyaan.items():
        if p.wajib and pid not in diisi:
            raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, f"Pertanyaan wajib belum dijawab: {p.teks}")
    if not diisi:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, "Tidak ada jawaban yang diisi")

    jawaban = JawabanSurvei(survei_id=survei.id, dijawab_pada=datetime.now(UTC), transaksi_id=body.transaksi_id, pelanggan_id=body.pelanggan_id)
    db.add(jawaban)
    await db.flush()
    for pid, j in diisi.items():
        rating = pertanyaan[pid].tipe == "rating"
        db.add(
            ItemJawabanSurvei(
                jawaban_survei_id=jawaban.id,
                pertanyaan_survei_id=pid,
                nilai_angka=j.nilai_angka if rating else None,
                nilai_teks=None if rating else (j.nilai_teks or "").strip(),
            )
        )
    await db.commit()
    return {"id": str(jawaban.id)}


@router.get("/{survei_id}/hasil", response_model=HasilSurveiOut)
async def hasil_survei(
    survei_id: uuid.UUID,
    toko_id: uuid.UUID = Depends(get_toko_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> HasilSurveiOut:
    await _wajib_izin(db, role_id, "pelanggan.kelola")
    survei = await _survei_milik_toko(db, survei_id, toko_id)
    jumlah = len(
        (
            await db.execute(
                select(JawabanSurvei.id).where(
                    JawabanSurvei.survei_id == survei.id, JawabanSurvei.deleted_at.is_(None)
                )
            )
        ).all()
    )
    hasil: list[HasilPertanyaanOut] = []
    for p in await _pertanyaan_survei(db, survei.id):
        items = (
            await db.execute(
                select(ItemJawabanSurvei)
                .where(ItemJawabanSurvei.pertanyaan_survei_id == p.id, ItemJawabanSurvei.deleted_at.is_(None))
                .order_by(ItemJawabanSurvei.created_at.desc())
            )
        ).scalars().all()
        keluaran = HasilPertanyaanOut(pertanyaan_id=p.id, teks=p.teks, tipe=p.tipe, jumlah_jawaban=len(items))
        if p.tipe == "rating":
            angka = [i.nilai_angka for i in items if i.nilai_angka is not None]
            if angka:
                keluaran.rata_rata = round(sum(angka) / len(angka), 2)
            keluaran.sebaran = {str(n): angka.count(n) for n in range(_RATING_MIN, _RATING_MAX + 1)}
        elif p.tipe == "pilihan":
            keluaran.sebaran = {o: sum(1 for i in items if i.nilai_teks == o) for o in (p.opsi or [])}
        else:
            keluaran.komentar = [i.nilai_teks for i in items if i.nilai_teks][:20]
        hasil.append(keluaran)
    return HasilSurveiOut(survei_id=survei.id, judul=survei.judul, jumlah_responden=jumlah, pertanyaan=hasil)
