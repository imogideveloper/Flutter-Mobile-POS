"""Lookup kecil yang dipakai saat checkout: pajak, promo, metode_bayar.
Digabung satu file (bukan 3 router terpisah) karena masing-masing hanya
butuh list+create sederhana, tanpa logika tambahan."""

import uuid
from datetime import UTC, datetime

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_db
from app.core.deps import get_pengguna_id, get_role_id, get_toko_id
from app.models.produk import Produk
from app.models.promo import Pajak, Promo, PromoOutlet, PromoProduk
from app.models.transaksi import MetodeBayar
from app.schemas.penjualan_setup import (
    IdsIn,
    MetodeBayarIn,
    MetodeBayarOut,
    MetodeBayarUpdateIn,
    PajakIn,
    PajakOut,
    PajakUpdateIn,
    PromoIn,
    PromoOut,
    PromoUpdateIn,
)
from app.services.audit_service import catat_audit
from app.services.fitur_service import has_fitur, require_fitur, tolak_fitur_terkunci
from app.services.izin_service import has_izin
from app.services.kepemilikan import get_outlet_milik_toko

router = APIRouter(tags=["penjualan-setup"])


async def _wajib_izin_promo_kelola(db: AsyncSession, role_id: uuid.UUID) -> None:
    if not await has_izin(db, role_id, "promo.kelola"):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Role ini tidak punya izin promo.kelola")


@router.get("/pajak", response_model=list[PajakOut])
async def daftar_pajak(
    toko_id: uuid.UUID = Depends(get_toko_id), db: AsyncSession = Depends(get_db)
) -> list[Pajak]:
    rows = await db.execute(
        select(Pajak).where(Pajak.toko_id == toko_id, Pajak.deleted_at.is_(None)).order_by(Pajak.urutan)
    )
    return list(rows.scalars().all())


@router.post("/pajak", response_model=PajakOut, status_code=status.HTTP_201_CREATED)
async def tambah_pajak(
    body: PajakIn,
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> Pajak:
    await _wajib_izin_promo_kelola(db, role_id)
    pajak = Pajak(toko_id=toko_id, **body.model_dump())
    db.add(pajak)
    await db.flush()
    await catat_audit(
        db, toko_id=toko_id, pengguna_id=pengguna_id, aksi="tambah_pajak",
        tabel="pajak", record_id=pajak.id, data_baru=body.model_dump(mode="json"),
    )
    await db.commit()
    await db.refresh(pajak)
    return pajak


async def _ambil_pajak_milik_toko(db: AsyncSession, pajak_id: uuid.UUID, toko_id: uuid.UUID) -> Pajak:
    pajak = await db.get(Pajak, pajak_id)
    if pajak is None or pajak.toko_id != toko_id or pajak.deleted_at is not None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Pajak tidak ditemukan")
    return pajak


@router.patch("/pajak/{pajak_id}", response_model=PajakOut)
async def ubah_pajak(
    pajak_id: uuid.UUID,
    body: PajakUpdateIn,
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> Pajak:
    await _wajib_izin_promo_kelola(db, role_id)
    pajak = await _ambil_pajak_milik_toko(db, pajak_id, toko_id)

    perubahan = body.model_dump(exclude_unset=True)
    data_lama = {k: str(getattr(pajak, k)) for k in perubahan}
    for field, value in perubahan.items():
        setattr(pajak, field, value)
    await catat_audit(
        db, toko_id=toko_id, pengguna_id=pengguna_id, aksi="ubah_pajak",
        tabel="pajak", record_id=pajak.id,
        data_lama=data_lama, data_baru={k: str(v) for k, v in perubahan.items()},
    )
    await db.commit()
    await db.refresh(pajak)
    return pajak


@router.delete("/pajak/{pajak_id}", status_code=status.HTTP_204_NO_CONTENT)
async def hapus_pajak(
    pajak_id: uuid.UUID,
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> None:
    await _wajib_izin_promo_kelola(db, role_id)
    pajak = await _ambil_pajak_milik_toko(db, pajak_id, toko_id)
    pajak.deleted_at = datetime.now(UTC)
    await catat_audit(
        db, toko_id=toko_id, pengguna_id=pengguna_id, aksi="hapus_pajak",
        tabel="pajak", record_id=pajak.id, data_lama={"nama": pajak.nama},
    )
    await db.commit()


@router.get("/promo", response_model=list[PromoOut], dependencies=[Depends(require_fitur("diskon"))])
async def daftar_promo(
    toko_id: uuid.UUID = Depends(get_toko_id), db: AsyncSession = Depends(get_db)
) -> list[Promo]:
    rows = await db.execute(
        select(Promo).where(Promo.toko_id == toko_id, Promo.deleted_at.is_(None))
    )
    return list(rows.scalars().all())


@router.post(
    "/promo",
    response_model=PromoOut,
    status_code=status.HTTP_201_CREATED,
    dependencies=[Depends(require_fitur("diskon"))],
)
async def tambah_promo(
    body: PromoIn,
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> Promo:
    await _wajib_izin_promo_kelola(db, role_id)
    # Promo ulang tahun adalah fitur sendiri (IMOGI no. 56): menyalakannya digerbang paket.
    if body.khusus_ulang_tahun and not await has_fitur(db, toko_id, "birthday_promo"):
        await tolak_fitur_terkunci(db, "birthday_promo")
    promo = Promo(toko_id=toko_id, **body.model_dump())
    db.add(promo)
    await db.flush()
    await catat_audit(
        db, toko_id=toko_id, pengguna_id=pengguna_id, aksi="tambah_promo",
        tabel="promo", record_id=promo.id, data_baru=body.model_dump(mode="json"),
    )
    await db.commit()
    await db.refresh(promo)
    return promo


async def _ambil_promo_milik_toko(db: AsyncSession, promo_id: uuid.UUID, toko_id: uuid.UUID) -> Promo:
    promo = await db.get(Promo, promo_id)
    if promo is None or promo.toko_id != toko_id or promo.deleted_at is not None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Promo tidak ditemukan")
    return promo


@router.patch("/promo/{promo_id}", response_model=PromoOut, dependencies=[Depends(require_fitur("diskon"))])
async def ubah_promo(
    promo_id: uuid.UUID,
    body: PromoUpdateIn,
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> Promo:
    await _wajib_izin_promo_kelola(db, role_id)
    promo = await _ambil_promo_milik_toko(db, promo_id, toko_id)

    perubahan = body.model_dump(exclude_unset=True)
    # Hanya digerbang saat benar-benar berubah menjadi aktif (klien mengirim ulang seluruh isian).
    if (
        perubahan.get("khusus_ulang_tahun") is True
        and promo.khusus_ulang_tahun is not True
        and not await has_fitur(db, toko_id, "birthday_promo")
    ):
        await tolak_fitur_terkunci(db, "birthday_promo")
    data_lama = {k: str(getattr(promo, k)) for k in perubahan}
    for field, value in perubahan.items():
        setattr(promo, field, value)
    await catat_audit(
        db, toko_id=toko_id, pengguna_id=pengguna_id, aksi="ubah_promo",
        tabel="promo", record_id=promo.id,
        data_lama=data_lama, data_baru={k: str(v) for k, v in perubahan.items()},
    )
    await db.commit()
    await db.refresh(promo)
    return promo


@router.delete("/promo/{promo_id}", status_code=status.HTTP_204_NO_CONTENT, dependencies=[Depends(require_fitur("diskon"))])
async def hapus_promo(
    promo_id: uuid.UUID,
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> None:
    await _wajib_izin_promo_kelola(db, role_id)
    promo = await _ambil_promo_milik_toko(db, promo_id, toko_id)
    promo.deleted_at = datetime.now(UTC)
    # promo_produk/promo_outlet (link murni, tanpa deleted_at sendiri) TIDAK
    # perlu dibersihkan - promo induknya sudah soft-deleted, tidak pernah
    # lagi dibaca lewat _ambil_promo_milik_toko/daftar_promo di atas.
    await catat_audit(
        db, toko_id=toko_id, pengguna_id=pengguna_id, aksi="hapus_promo",
        tabel="promo", record_id=promo.id, data_lama={"nama": promo.nama},
    )
    await db.commit()


@router.get("/promo/{promo_id}/produk", response_model=list[uuid.UUID], dependencies=[Depends(require_fitur("diskon"))])
async def daftar_promo_produk(
    promo_id: uuid.UUID, toko_id: uuid.UUID = Depends(get_toko_id), db: AsyncSession = Depends(get_db)
) -> list[uuid.UUID]:
    await _ambil_promo_milik_toko(db, promo_id, toko_id)
    rows = (await db.execute(select(PromoProduk.produk_id).where(PromoProduk.promo_id == promo_id))).scalars().all()
    return list(rows)


@router.put("/promo/{promo_id}/produk", status_code=status.HTTP_204_NO_CONTENT, dependencies=[Depends(require_fitur("diskon"))])
async def atur_promo_produk(
    promo_id: uuid.UUID,
    body: IdsIn,
    toko_id: uuid.UUID = Depends(get_toko_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> None:
    """Replace-all (bukan tambah/kurang satu-satu) - sama pola dgn
    PUT /produk/{id}/grup-modifier/{grup_id} yang sudah ada."""
    await _wajib_izin_promo_kelola(db, role_id)
    await _ambil_promo_milik_toko(db, promo_id, toko_id)
    if body.ids:
        ditemukan = set(
            (await db.execute(select(Produk.id).where(Produk.id.in_(body.ids), Produk.toko_id == toko_id)))
            .scalars()
            .all()
        )
        if ditemukan != set(body.ids):
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Ada produk yang tidak ditemukan")

    await db.execute(delete(PromoProduk).where(PromoProduk.promo_id == promo_id))
    for produk_id in body.ids:
        db.add(PromoProduk(promo_id=promo_id, produk_id=produk_id))
    await db.commit()


@router.get("/promo/{promo_id}/outlet", response_model=list[uuid.UUID], dependencies=[Depends(require_fitur("diskon"))])
async def daftar_promo_outlet(
    promo_id: uuid.UUID, toko_id: uuid.UUID = Depends(get_toko_id), db: AsyncSession = Depends(get_db)
) -> list[uuid.UUID]:
    await _ambil_promo_milik_toko(db, promo_id, toko_id)
    rows = (await db.execute(select(PromoOutlet.outlet_id).where(PromoOutlet.promo_id == promo_id))).scalars().all()
    return list(rows)


@router.put("/promo/{promo_id}/outlet", status_code=status.HTTP_204_NO_CONTENT, dependencies=[Depends(require_fitur("diskon"))])
async def atur_promo_outlet(
    promo_id: uuid.UUID,
    body: IdsIn,
    toko_id: uuid.UUID = Depends(get_toko_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> None:
    await _wajib_izin_promo_kelola(db, role_id)
    await _ambil_promo_milik_toko(db, promo_id, toko_id)
    for outlet_id in body.ids:
        await get_outlet_milik_toko(db, outlet_id, toko_id)

    await db.execute(delete(PromoOutlet).where(PromoOutlet.promo_id == promo_id))
    for outlet_id in body.ids:
        db.add(PromoOutlet(promo_id=promo_id, outlet_id=outlet_id))
    await db.commit()


@router.get("/metode-bayar", response_model=list[MetodeBayarOut])
async def daftar_metode_bayar(
    toko_id: uuid.UUID = Depends(get_toko_id), db: AsyncSession = Depends(get_db)
) -> list[MetodeBayar]:
    rows = await db.execute(
        select(MetodeBayar).where(MetodeBayar.toko_id == toko_id, MetodeBayar.deleted_at.is_(None))
    )
    return list(rows.scalars().all())


@router.post("/metode-bayar", response_model=MetodeBayarOut, status_code=status.HTTP_201_CREATED)
async def tambah_metode_bayar(
    body: MetodeBayarIn, toko_id: uuid.UUID = Depends(get_toko_id), db: AsyncSession = Depends(get_db)
) -> MetodeBayar:
    metode = MetodeBayar(toko_id=toko_id, **body.model_dump())
    db.add(metode)
    await db.commit()
    await db.refresh(metode)
    return metode


@router.patch("/metode-bayar/{metode_bayar_id}", response_model=MetodeBayarOut)
async def ubah_metode_bayar(
    metode_bayar_id: uuid.UUID,
    body: MetodeBayarUpdateIn,
    toko_id: uuid.UUID = Depends(get_toko_id),
    db: AsyncSession = Depends(get_db),
) -> MetodeBayar:
    metode = await db.get(MetodeBayar, metode_bayar_id)
    if metode is None or metode.toko_id != toko_id or metode.deleted_at is not None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Metode bayar tidak ditemukan")

    perubahan = body.model_dump(exclude_unset=True)
    # Ganti nama/label & urutan digate 'label_pembayaran' (tahap 4 bagian
    # B.3) - aktif/nonaktif tidak pernah digate.
    if ("nama" in perubahan or "urutan" in perubahan) and not await has_fitur(
        db, toko_id, "label_pembayaran"
    ):
        await tolak_fitur_terkunci(db, "label_pembayaran")

    for field, value in perubahan.items():
        setattr(metode, field, value)
    await db.commit()
    await db.refresh(metode)
    return metode
