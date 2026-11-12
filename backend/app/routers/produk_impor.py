"""Unggah produk massal via template (IMOGI no. 38, fitur `ekspor_impor`, paket Starter).

Klien mengurai berkas CSV lalu mengirim baris-barisnya; server memvalidasi tiap baris dan
menyimpan yang valid. `simulasi=true` hanya memeriksa. Tiap baris berdiri sendiri: baris yang
salah ditolak dengan alasan, baris lain tetap masuk.
"""

import uuid
from decimal import Decimal

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_db
from app.core.deps import get_pengguna_id, get_role_id, get_toko_id
from app.models.produk import Kategori, Produk
from app.schemas.produk_impor import HasilBarisImporOut, ImporProdukIn, ImporProdukOut
from app.services.audit_service import catat_audit
from app.services.fitur_service import paket_efektif, require_fitur
from app.services.izin_service import has_izin

router = APIRouter(tags=["produk"], dependencies=[Depends(require_fitur("ekspor_impor"))])


def _bersih(teks: str | None) -> str | None:
    teks = (teks or "").strip()
    return teks or None


@router.post("/produk/impor", response_model=ImporProdukOut)
async def impor_produk(
    body: ImporProdukIn,
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> ImporProdukOut:
    if not await has_izin(db, role_id, "produk.kelola"):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Role ini tidak punya izin produk.kelola")

    paket = await paket_efektif(db, toko_id)
    jumlah_ada = await db.scalar(
        select(func.count()).select_from(Produk).where(Produk.toko_id == toko_id, Produk.deleted_at.is_(None))
    )
    sisa_kuota = None if paket.maks_produk is None else max(paket.maks_produk - int(jumlah_ada or 0), 0)

    produk_ada = (
        await db.execute(select(Produk.sku, Produk.barcode).where(Produk.toko_id == toko_id, Produk.deleted_at.is_(None)))
    ).all()
    sku_dipakai = {s.lower() for s, _ in produk_ada if s}
    barcode_dipakai = {b.lower() for _, b in produk_ada if b}
    # Soft-delete tetap menahan unique constraint (toko, sku/barcode): ikut dihitung agar tidak bentrok di DB.
    bekas = (
        await db.execute(select(Produk.sku, Produk.barcode).where(Produk.toko_id == toko_id, Produk.deleted_at.is_not(None)))
    ).all()
    sku_dipakai |= {s.lower() for s, _ in bekas if s}
    barcode_dipakai |= {b.lower() for _, b in bekas if b}

    kategori_ada = {
        k.nama.strip().lower(): k
        for k in (
            await db.execute(select(Kategori).where(Kategori.toko_id == toko_id, Kategori.deleted_at.is_(None)))
        ).scalars()
    }
    kategori_baru: dict[str, Kategori] = {}

    hasil: list[HasilBarisImporOut] = []
    diterima = 0
    for nomor, baris in enumerate(body.baris, start=1):
        nama = baris.nama.strip()

        def tolak(pesan: str) -> None:
            hasil.append(HasilBarisImporOut(nomor=nomor, nama=nama, status="ditolak", pesan=pesan))

        if not nama:
            tolak("Nama produk wajib diisi")
            continue
        if baris.harga_jual < 0 or baris.hpp < 0:
            tolak("Harga jual dan HPP tidak boleh negatif")
            continue
        if baris.harga_jual > Decimal("99999999999") or baris.hpp > Decimal("99999999999"):
            tolak("Harga terlalu besar")
            continue
        sku, barcode = _bersih(baris.sku), _bersih(baris.barcode)
        if sku and sku.lower() in sku_dipakai:
            tolak(f"SKU {sku} sudah dipakai")
            continue
        if barcode and barcode.lower() in barcode_dipakai:
            tolak(f"Barcode {barcode} sudah dipakai")
            continue
        if sisa_kuota is not None and diterima + 1 > sisa_kuota:
            tolak(f"Kuota produk paket ({paket.maks_produk}) habis")
            continue

        kategori = None
        nama_kategori = _bersih(baris.kategori)
        if nama_kategori:
            kunci = nama_kategori.lower()
            kategori = kategori_ada.get(kunci) or kategori_baru.get(kunci)
            if kategori is None:
                kategori = Kategori(toko_id=toko_id, nama=nama_kategori)
                if not body.simulasi:
                    db.add(kategori)
                    await db.flush()
                kategori_baru[kunci] = kategori

        if sku:
            sku_dipakai.add(sku.lower())
        if barcode:
            barcode_dipakai.add(barcode.lower())
        if not body.simulasi:
            db.add(
                Produk(
                    toko_id=toko_id,
                    kategori_id=kategori.id if kategori is not None else None,
                    sku=sku,
                    barcode=barcode,
                    nama=nama,
                    deskripsi=_bersih(baris.deskripsi),
                    hpp=baris.hpp,
                    harga_jual=baris.harga_jual,
                )
            )
        diterima += 1
        hasil.append(HasilBarisImporOut(nomor=nomor, nama=nama, status="diterima"))

    if not body.simulasi and diterima:
        await db.flush()
        await catat_audit(
            db, toko_id=toko_id, pengguna_id=pengguna_id, aksi="impor_produk",
            tabel="produk", record_id=None, data_baru={"diterima": diterima, "total_baris": len(body.baris)},
        )
        await db.commit()
    elif not body.simulasi:
        await db.rollback()

    return ImporProdukOut(
        simulasi=body.simulasi,
        diterima=diterima,
        ditolak=len(body.baris) - diterima,
        kategori_baru=[k.nama for k in kategori_baru.values()],
        hasil=hasil,
    )
