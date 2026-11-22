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
from app.models.outlet import Outlet
from app.models.produk import Kategori, Produk
from app.schemas.produk_impor import HasilBarisImporOut, ImporProdukIn, ImporProdukOut
from app.services.audit_service import catat_audit
from app.services.fitur_service import paket_efektif, require_fitur
from app.services.izin_service import has_izin
from app.services.stok_service import catat_mutasi

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

    produk_aktif = list(
        (await db.execute(select(Produk).where(Produk.toko_id == toko_id, Produk.deleted_at.is_(None)))).scalars()
    )
    sku_dipakai = {p.sku.lower() for p in produk_aktif if p.sku}
    barcode_dipakai = {p.barcode.lower() for p in produk_aktif if p.barcode}
    produk_by_sku = {p.sku.lower(): p for p in produk_aktif if p.sku}
    produk_by_barcode = {p.barcode.lower(): p for p in produk_aktif if p.barcode}
    boleh_stok = await has_izin(db, role_id, "stok.kelola")
    if body.outlet_id is not None:
        outlet = await db.get(Outlet, body.outlet_id)
        if outlet is None or outlet.toko_id != toko_id:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Outlet tidak ditemukan")
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
    diperbarui = 0
    for nomor, baris in enumerate(body.baris, start=1):
        nama = baris.nama.strip()

        def tolak(pesan: str) -> None:
            hasil.append(HasilBarisImporOut(nomor=nomor, nama=nama, status="ditolak", pesan=pesan))

        if not nama:
            tolak("Nama produk wajib diisi")
            continue
        harga_jual = baris.harga_jual if baris.harga_jual is not None else Decimal("0")
        hpp = baris.hpp if baris.hpp is not None else Decimal("0")
        if harga_jual < 0 or hpp < 0:
            tolak("Harga jual dan HPP tidak boleh negatif")
            continue
        if harga_jual > Decimal("99999999999") or hpp > Decimal("99999999999"):
            tolak("Harga terlalu besar")
            continue
        sku, barcode = _bersih(baris.sku), _bersih(baris.barcode)

        if body.perbarui_yang_ada:
            cocok_sku = produk_by_sku.get(sku.lower()) if sku else None
            cocok_barcode = produk_by_barcode.get(barcode.lower()) if barcode else None
            if cocok_sku is not None and cocok_barcode is not None and cocok_sku.id != cocok_barcode.id:
                tolak("SKU dan barcode milik dua produk yang berbeda")
                continue
            ada = cocok_sku or cocok_barcode
            if ada is not None:
                nama_kategori = _bersih(baris.kategori)
                kategori_ubah = None
                if nama_kategori:
                    kunci = nama_kategori.lower()
                    kategori_ubah = kategori_ada.get(kunci) or kategori_baru.get(kunci)
                    if kategori_ubah is None:
                        kategori_ubah = Kategori(toko_id=toko_id, nama=nama_kategori)
                        if not body.simulasi:
                            db.add(kategori_ubah)
                            await db.flush()
                        kategori_baru[kunci] = kategori_ubah
                if not body.simulasi:
                    ada.nama = nama
                    if baris.harga_jual is not None:
                        ada.harga_jual = baris.harga_jual
                    if baris.hpp is not None:
                        ada.hpp = baris.hpp
                    if kategori_ubah is not None:
                        ada.kategori_id = kategori_ubah.id
                    if _bersih(baris.deskripsi):
                        ada.deskripsi = _bersih(baris.deskripsi)
                diterima += 1
                diperbarui += 1
                hasil.append(HasilBarisImporOut(nomor=nomor, nama=nama, status="diperbarui"))
                continue

        if sku and sku.lower() in sku_dipakai:
            tolak(f"SKU {sku} sudah dipakai")
            continue
        if barcode and barcode.lower() in barcode_dipakai:
            tolak(f"Barcode {barcode} sudah dipakai")
            continue
        stok_awal = baris.stok_awal if baris.stok_awal is not None and baris.stok_awal > 0 else None
        if stok_awal is not None:
            if stok_awal > Decimal("99999999"):
                tolak("Stok awal terlalu besar")
                continue
            if not boleh_stok:
                tolak("Role ini tidak punya izin stok.kelola untuk mengisi stok awal")
                continue
            if body.outlet_id is None:
                tolak("Outlet wajib dipilih untuk mengisi stok awal")
                continue
        if sisa_kuota is not None and (diterima - diperbarui) + 1 > sisa_kuota:
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
            produk_baru = Produk(
                toko_id=toko_id,
                kategori_id=kategori.id if kategori is not None else None,
                sku=sku,
                barcode=barcode,
                nama=nama,
                deskripsi=_bersih(baris.deskripsi),
                hpp=hpp,
                harga_jual=harga_jual,
            )
            db.add(produk_baru)
            if stok_awal is not None:
                await db.flush()
                await catat_mutasi(
                    db, toko_id=toko_id, outlet_id=body.outlet_id, produk_id=produk_baru.id, varian_id=None,
                    jenis="stok_awal", qty=stok_awal, hpp_satuan=hpp, catatan="Stok awal dari impor produk",
                    dibuat_oleh=pengguna_id,
                )
        diterima += 1
        hasil.append(HasilBarisImporOut(nomor=nomor, nama=nama, status="diterima"))

    if not body.simulasi and diterima:
        await db.flush()
        await catat_audit(
            db, toko_id=toko_id, pengguna_id=pengguna_id, aksi="impor_produk",
            tabel="produk", record_id=None, data_baru={"diterima": diterima, "diperbarui": diperbarui, "total_baris": len(body.baris)},
        )
        await db.commit()
    elif not body.simulasi:
        await db.rollback()

    return ImporProdukOut(
        simulasi=body.simulasi,
        diterima=diterima,
        diperbarui=diperbarui,
        ditolak=len(body.baris) - diterima,
        kategori_baru=[k.nama for k in kategori_baru.values()],
        hasil=hasil,
    )
