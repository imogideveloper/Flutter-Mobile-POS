"""Modul 3 (lanjutan) - produk_varian, harga_outlet, grup_modifier +
modifier, produk_grup_modifier, resep, bundling_item, harga_grosir.
Dipisah dari produk.py supaya file itu tidak kepanjangan."""

import uuid
from datetime import UTC, datetime

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_db
from app.core.deps import get_pengguna_id, get_role_id, get_toko_id
from app.models.order import ProdukPajak
from app.models.outlet import Outlet
from app.models.produk import (
    BundlingItem,
    GrupModifier,
    HargaGrosir,
    HargaOutlet,
    Modifier,
    Produk,
    ProdukGrupModifier,
    ProdukVarian,
    Resep,
)
from app.models.promo import Pajak
from app.routers.produk import ambil_produk_milik_toko
from app.schemas.produk_lanjutan import (
    BundlingItemIn,
    BundlingItemOut,
    BundlingItemUpdateIn,
    GrupModifierIn,
    GrupModifierOut,
    GrupModifierUpdateIn,
    HargaGrosirIn,
    HargaGrosirOut,
    HargaGrosirUpdateIn,
    HargaOutletIn,
    HargaOutletOut,
    HargaOutletUpdateIn,
    ModifierIn,
    ModifierOut,
    ModifierUpdateIn,
    ProdukPajakOut,
    ProdukVarianIn,
    ProdukVarianOut,
    ProdukVarianUpdateIn,
    ResepIn,
    ResepOut,
    ResepUpdateIn,
)
from app.services.audit_service import catat_audit
from app.services.fitur_service import require_fitur
from app.services.izin_service import has_izin

router = APIRouter(tags=["produk-lanjutan"])


async def _wajib_izin_produk_kelola(db: AsyncSession, role_id: uuid.UUID) -> None:
    if not await has_izin(db, role_id, "produk.kelola"):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Role ini tidak punya izin produk.kelola")


async def _pastikan_varian_milik_produk(db: AsyncSession, varian_id: uuid.UUID | None, produk_id: uuid.UUID) -> None:
    """varian_id (kalau diisi) harus varian dari PRODUK INI, bukan cuma
    "varian milik toko ini" - varian_id milik produk lain (termasuk milik
    toko sendiri) juga tetap salah secara semantik, apalagi milik toko
    lain."""

    if varian_id is None:
        return
    varian = await db.get(ProdukVarian, varian_id)
    if varian is None or varian.produk_id != produk_id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Varian produk tidak ditemukan")


# ---------------------------------------------------------------- Varian --

@router.get("/produk/{produk_id}/varian", response_model=list[ProdukVarianOut])
async def daftar_varian(
    produk_id: uuid.UUID, toko_id: uuid.UUID = Depends(get_toko_id), db: AsyncSession = Depends(get_db)
) -> list[ProdukVarian]:
    await ambil_produk_milik_toko(produk_id, toko_id, db)
    rows = (
        await db.execute(
            select(ProdukVarian).where(ProdukVarian.produk_id == produk_id, ProdukVarian.deleted_at.is_(None))
        )
    ).scalars().all()
    return list(rows)


@router.post(
    "/produk/{produk_id}/varian", response_model=ProdukVarianOut, status_code=status.HTTP_201_CREATED
)
async def tambah_varian(
    produk_id: uuid.UUID,
    body: ProdukVarianIn,
    toko_id: uuid.UUID = Depends(get_toko_id),
    db: AsyncSession = Depends(get_db),
) -> ProdukVarian:
    await ambil_produk_milik_toko(produk_id, toko_id, db)
    varian = ProdukVarian(produk_id=produk_id, **body.model_dump())
    db.add(varian)
    await db.commit()
    await db.refresh(varian)
    return varian


async def _ambil_varian_milik_produk(db: AsyncSession, varian_id: uuid.UUID, produk_id: uuid.UUID) -> ProdukVarian:
    varian = await db.get(ProdukVarian, varian_id)
    if varian is None or varian.produk_id != produk_id or varian.deleted_at is not None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Varian tidak ditemukan")
    return varian


@router.patch("/produk/{produk_id}/varian/{varian_id}", response_model=ProdukVarianOut)
async def ubah_varian(
    produk_id: uuid.UUID,
    varian_id: uuid.UUID,
    body: ProdukVarianUpdateIn,
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> ProdukVarian:
    await _wajib_izin_produk_kelola(db, role_id)
    await ambil_produk_milik_toko(produk_id, toko_id, db)
    varian = await _ambil_varian_milik_produk(db, varian_id, produk_id)

    perubahan = body.model_dump(exclude_unset=True)
    data_lama = {k: str(getattr(varian, k)) for k in perubahan}
    for field, value in perubahan.items():
        setattr(varian, field, value)
    await catat_audit(
        db, toko_id=toko_id, pengguna_id=pengguna_id, aksi="ubah_varian",
        tabel="produk_varian", record_id=varian.id,
        data_lama=data_lama, data_baru={k: str(v) for k, v in perubahan.items()},
    )
    await db.commit()
    await db.refresh(varian)
    return varian


@router.delete("/produk/{produk_id}/varian/{varian_id}", status_code=status.HTTP_204_NO_CONTENT)
async def hapus_varian(
    produk_id: uuid.UUID,
    varian_id: uuid.UUID,
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> None:
    await _wajib_izin_produk_kelola(db, role_id)
    await ambil_produk_milik_toko(produk_id, toko_id, db)
    varian = await _ambil_varian_milik_produk(db, varian_id, produk_id)
    varian.deleted_at = datetime.now(UTC)
    await catat_audit(
        db, toko_id=toko_id, pengguna_id=pengguna_id, aksi="hapus_varian",
        tabel="produk_varian", record_id=varian.id, data_lama={"nama": varian.nama},
    )
    await db.commit()


# ------------------------------------------------------------ Grup modifier (toko-scoped) --

@router.get("/grup-modifier", response_model=list[GrupModifierOut])
async def daftar_grup_modifier(
    toko_id: uuid.UUID = Depends(get_toko_id), db: AsyncSession = Depends(get_db)
) -> list[GrupModifier]:
    rows = (
        await db.execute(select(GrupModifier).where(GrupModifier.toko_id == toko_id, GrupModifier.deleted_at.is_(None)))
    ).scalars().all()
    return list(rows)


@router.post("/grup-modifier", response_model=GrupModifierOut, status_code=status.HTTP_201_CREATED)
async def tambah_grup_modifier(
    body: GrupModifierIn, toko_id: uuid.UUID = Depends(get_toko_id), db: AsyncSession = Depends(get_db)
) -> GrupModifier:
    grup = GrupModifier(toko_id=toko_id, **body.model_dump())
    db.add(grup)
    await db.commit()
    await db.refresh(grup)
    return grup


async def _ambil_grup_modifier_milik_toko(
    db: AsyncSession, grup_modifier_id: uuid.UUID, toko_id: uuid.UUID
) -> GrupModifier:
    grup = await db.get(GrupModifier, grup_modifier_id)
    if grup is None or grup.toko_id != toko_id or grup.deleted_at is not None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Grup modifier tidak ditemukan")
    return grup


@router.patch("/grup-modifier/{grup_modifier_id}", response_model=GrupModifierOut)
async def ubah_grup_modifier(
    grup_modifier_id: uuid.UUID,
    body: GrupModifierUpdateIn,
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> GrupModifier:
    await _wajib_izin_produk_kelola(db, role_id)
    grup = await _ambil_grup_modifier_milik_toko(db, grup_modifier_id, toko_id)
    perubahan = body.model_dump(exclude_unset=True)
    data_lama = {k: str(getattr(grup, k)) for k in perubahan}
    for field, value in perubahan.items():
        setattr(grup, field, value)
    await catat_audit(
        db, toko_id=toko_id, pengguna_id=pengguna_id, aksi="ubah_grup_modifier",
        tabel="grup_modifier", record_id=grup.id,
        data_lama=data_lama, data_baru={k: str(v) for k, v in perubahan.items()},
    )
    await db.commit()
    await db.refresh(grup)
    return grup


@router.delete("/grup-modifier/{grup_modifier_id}", status_code=status.HTTP_204_NO_CONTENT)
async def hapus_grup_modifier(
    grup_modifier_id: uuid.UUID,
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> None:
    await _wajib_izin_produk_kelola(db, role_id)
    grup = await _ambil_grup_modifier_milik_toko(db, grup_modifier_id, toko_id)
    grup.deleted_at = datetime.now(UTC)
    await catat_audit(
        db, toko_id=toko_id, pengguna_id=pengguna_id, aksi="hapus_grup_modifier",
        tabel="grup_modifier", record_id=grup.id, data_lama={"nama": grup.nama},
    )
    await db.commit()


@router.get("/grup-modifier/{grup_modifier_id}/modifier", response_model=list[ModifierOut])
async def daftar_modifier(
    grup_modifier_id: uuid.UUID,
    toko_id: uuid.UUID = Depends(get_toko_id),
    db: AsyncSession = Depends(get_db),
) -> list[Modifier]:
    await _ambil_grup_modifier_milik_toko(db, grup_modifier_id, toko_id)
    rows = (
        await db.execute(
            select(Modifier)
            .where(Modifier.grup_modifier_id == grup_modifier_id, Modifier.deleted_at.is_(None))
            .order_by(Modifier.urutan)
        )
    ).scalars().all()
    return list(rows)


@router.post(
    "/grup-modifier/{grup_modifier_id}/modifier", response_model=ModifierOut, status_code=status.HTTP_201_CREATED
)
async def tambah_modifier(
    grup_modifier_id: uuid.UUID,
    body: ModifierIn,
    toko_id: uuid.UUID = Depends(get_toko_id),
    db: AsyncSession = Depends(get_db),
) -> Modifier:
    await _ambil_grup_modifier_milik_toko(db, grup_modifier_id, toko_id)
    modifier = Modifier(grup_modifier_id=grup_modifier_id, **body.model_dump())
    db.add(modifier)
    await db.commit()
    await db.refresh(modifier)
    return modifier


async def _ambil_modifier_milik_grup(db: AsyncSession, modifier_id: uuid.UUID, grup_modifier_id: uuid.UUID) -> Modifier:
    modifier = await db.get(Modifier, modifier_id)
    if modifier is None or modifier.grup_modifier_id != grup_modifier_id or modifier.deleted_at is not None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Modifier tidak ditemukan")
    return modifier


@router.patch("/grup-modifier/{grup_modifier_id}/modifier/{modifier_id}", response_model=ModifierOut)
async def ubah_modifier(
    grup_modifier_id: uuid.UUID,
    modifier_id: uuid.UUID,
    body: ModifierUpdateIn,
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> Modifier:
    await _wajib_izin_produk_kelola(db, role_id)
    await _ambil_grup_modifier_milik_toko(db, grup_modifier_id, toko_id)
    modifier = await _ambil_modifier_milik_grup(db, modifier_id, grup_modifier_id)

    perubahan = body.model_dump(exclude_unset=True)
    data_lama = {k: str(getattr(modifier, k)) for k in perubahan}
    for field, value in perubahan.items():
        setattr(modifier, field, value)
    await catat_audit(
        db, toko_id=toko_id, pengguna_id=pengguna_id, aksi="ubah_modifier",
        tabel="modifier", record_id=modifier.id,
        data_lama=data_lama, data_baru={k: str(v) for k, v in perubahan.items()},
    )
    await db.commit()
    await db.refresh(modifier)
    return modifier


@router.delete("/grup-modifier/{grup_modifier_id}/modifier/{modifier_id}", status_code=status.HTTP_204_NO_CONTENT)
async def hapus_modifier(
    grup_modifier_id: uuid.UUID,
    modifier_id: uuid.UUID,
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> None:
    await _wajib_izin_produk_kelola(db, role_id)
    await _ambil_grup_modifier_milik_toko(db, grup_modifier_id, toko_id)
    modifier = await _ambil_modifier_milik_grup(db, modifier_id, grup_modifier_id)
    modifier.deleted_at = datetime.now(UTC)
    await catat_audit(
        db, toko_id=toko_id, pengguna_id=pengguna_id, aksi="hapus_modifier",
        tabel="modifier", record_id=modifier.id, data_lama={"nama": modifier.nama},
    )
    await db.commit()


@router.put("/produk/{produk_id}/grup-modifier/{grup_modifier_id}", status_code=status.HTTP_204_NO_CONTENT)
async def tautkan_grup_modifier_ke_produk(
    produk_id: uuid.UUID,
    grup_modifier_id: uuid.UUID,
    toko_id: uuid.UUID = Depends(get_toko_id),
    db: AsyncSession = Depends(get_db),
) -> None:
    await ambil_produk_milik_toko(produk_id, toko_id, db)
    await _ambil_grup_modifier_milik_toko(db, grup_modifier_id, toko_id)

    existing = await db.get(ProdukGrupModifier, {"produk_id": produk_id, "grup_modifier_id": grup_modifier_id})
    if existing is None:
        db.add(ProdukGrupModifier(produk_id=produk_id, grup_modifier_id=grup_modifier_id))
        await db.commit()


@router.get("/produk/{produk_id}/grup-modifier", response_model=list[GrupModifierOut])
async def daftar_grup_modifier_produk(
    produk_id: uuid.UUID, toko_id: uuid.UUID = Depends(get_toko_id), db: AsyncSession = Depends(get_db)
) -> list[GrupModifier]:
    await ambil_produk_milik_toko(produk_id, toko_id, db)
    rows = (
        await db.execute(
            select(GrupModifier)
            .join(ProdukGrupModifier, ProdukGrupModifier.grup_modifier_id == GrupModifier.id)
            .where(ProdukGrupModifier.produk_id == produk_id)
        )
    ).scalars().all()
    return list(rows)


# ---------------------------------------------------------------- Resep --

@router.get("/produk/{produk_id}/resep", response_model=list[ResepOut], dependencies=[Depends(require_fitur("resep"))])
async def daftar_resep(
    produk_id: uuid.UUID, toko_id: uuid.UUID = Depends(get_toko_id), db: AsyncSession = Depends(get_db)
) -> list[ResepOut]:
    await ambil_produk_milik_toko(produk_id, toko_id, db)
    rows = (
        await db.execute(
            select(Resep, Produk).join(Produk, Produk.id == Resep.bahan_id).where(Resep.produk_id == produk_id, Resep.deleted_at.is_(None))
        )
    ).all()
    return [
        ResepOut(id=r.id, produk_id=r.produk_id, varian_id=r.varian_id, bahan_id=r.bahan_id, nama_bahan=bahan.nama, qty=r.qty)
        for r, bahan in rows
    ]


@router.post(
    "/produk/{produk_id}/resep", response_model=ResepOut, status_code=status.HTTP_201_CREATED,
    dependencies=[Depends(require_fitur("resep"))],
)
async def tambah_resep(
    produk_id: uuid.UUID,
    body: ResepIn,
    toko_id: uuid.UUID = Depends(get_toko_id),
    db: AsyncSession = Depends(get_db),
) -> ResepOut:
    await ambil_produk_milik_toko(produk_id, toko_id, db)
    bahan = await ambil_produk_milik_toko(body.bahan_id, toko_id, db)
    await _pastikan_varian_milik_produk(db, body.varian_id, produk_id)

    resep = Resep(produk_id=produk_id, varian_id=body.varian_id, bahan_id=body.bahan_id, qty=body.qty)
    db.add(resep)
    await db.commit()
    await db.refresh(resep)
    return ResepOut(
        id=resep.id, produk_id=resep.produk_id, varian_id=resep.varian_id, bahan_id=resep.bahan_id,
        nama_bahan=bahan.nama, qty=resep.qty,
    )


async def _ambil_resep_milik_produk(db: AsyncSession, resep_id: uuid.UUID, produk_id: uuid.UUID) -> Resep:
    resep = await db.get(Resep, resep_id)
    if resep is None or resep.produk_id != produk_id or resep.deleted_at is not None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Resep tidak ditemukan")
    return resep


@router.patch(
    "/produk/{produk_id}/resep/{resep_id}", response_model=ResepOut,
    dependencies=[Depends(require_fitur("resep"))],
)
async def ubah_resep(
    produk_id: uuid.UUID,
    resep_id: uuid.UUID,
    body: ResepUpdateIn,
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> ResepOut:
    await _wajib_izin_produk_kelola(db, role_id)
    await ambil_produk_milik_toko(produk_id, toko_id, db)
    resep = await _ambil_resep_milik_produk(db, resep_id, produk_id)

    perubahan = body.model_dump(exclude_unset=True)
    if "varian_id" in perubahan:
        await _pastikan_varian_milik_produk(db, perubahan["varian_id"], produk_id)
    data_lama = {k: str(getattr(resep, k)) for k in perubahan}
    for field, value in perubahan.items():
        setattr(resep, field, value)
    bahan = await ambil_produk_milik_toko(resep.bahan_id, toko_id, db)
    await catat_audit(
        db, toko_id=toko_id, pengguna_id=pengguna_id, aksi="ubah_resep",
        tabel="resep", record_id=resep.id,
        data_lama=data_lama, data_baru={k: str(v) for k, v in perubahan.items()},
    )
    await db.commit()
    await db.refresh(resep)
    return ResepOut(
        id=resep.id, produk_id=resep.produk_id, varian_id=resep.varian_id, bahan_id=resep.bahan_id,
        nama_bahan=bahan.nama, qty=resep.qty,
    )


@router.delete(
    "/produk/{produk_id}/resep/{resep_id}", status_code=status.HTTP_204_NO_CONTENT,
    dependencies=[Depends(require_fitur("resep"))],
)
async def hapus_resep(
    produk_id: uuid.UUID,
    resep_id: uuid.UUID,
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> None:
    await _wajib_izin_produk_kelola(db, role_id)
    await ambil_produk_milik_toko(produk_id, toko_id, db)
    resep = await _ambil_resep_milik_produk(db, resep_id, produk_id)
    resep.deleted_at = datetime.now(UTC)
    await catat_audit(
        db, toko_id=toko_id, pengguna_id=pengguna_id, aksi="hapus_resep",
        tabel="resep", record_id=resep.id, data_lama={"bahan_id": str(resep.bahan_id)},
    )
    await db.commit()


# ------------------------------------------------------------- Bundling --

@router.get(
    "/produk/{produk_id}/bundling", response_model=list[BundlingItemOut],
    dependencies=[Depends(require_fitur("bundling"))],
)
async def daftar_bundling(
    produk_id: uuid.UUID, toko_id: uuid.UUID = Depends(get_toko_id), db: AsyncSession = Depends(get_db)
) -> list[BundlingItemOut]:
    await ambil_produk_milik_toko(produk_id, toko_id, db)
    rows = (
        await db.execute(
            select(BundlingItem, Produk)
            .join(Produk, Produk.id == BundlingItem.produk_id)
            .where(BundlingItem.bundling_produk_id == produk_id, BundlingItem.deleted_at.is_(None))
        )
    ).all()
    return [
        BundlingItemOut(
            id=b.id, bundling_produk_id=b.bundling_produk_id, produk_id=b.produk_id, nama_produk=isi.nama,
            varian_id=b.varian_id, qty=b.qty,
        )
        for b, isi in rows
    ]


@router.post(
    "/produk/{produk_id}/bundling", response_model=BundlingItemOut, status_code=status.HTTP_201_CREATED,
    dependencies=[Depends(require_fitur("bundling"))],
)
async def tambah_bundling(
    produk_id: uuid.UUID,
    body: BundlingItemIn,
    toko_id: uuid.UUID = Depends(get_toko_id),
    db: AsyncSession = Depends(get_db),
) -> BundlingItemOut:
    bundling_produk = await ambil_produk_milik_toko(produk_id, toko_id, db)
    if bundling_produk.id == body.produk_id:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Produk bundling tidak boleh berisi dirinya sendiri")
    isi = await ambil_produk_milik_toko(body.produk_id, toko_id, db)
    if isi.tipe == "bundling":
        # Aturan dokumen harga (docs/aturan_harga.md, bagian Bundling):
        # bundle tidak boleh berisi bundle lain - checkout_service hanya
        # meng-expand SATU level komponen, bundle-dalam-bundle akan diam2
        # gagal potong stok level kedua kalau ini tidak ditolak di sini.
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Produk bundling tidak boleh berisi produk bundling lain")
    await _pastikan_varian_milik_produk(db, body.varian_id, body.produk_id)

    item = BundlingItem(bundling_produk_id=produk_id, produk_id=body.produk_id, varian_id=body.varian_id, qty=body.qty)
    db.add(item)
    await db.commit()
    await db.refresh(item)
    return BundlingItemOut(
        id=item.id, bundling_produk_id=item.bundling_produk_id, produk_id=item.produk_id, nama_produk=isi.nama,
        varian_id=item.varian_id, qty=item.qty,
    )


async def _ambil_bundling_milik_produk(db: AsyncSession, bundling_id: uuid.UUID, produk_id: uuid.UUID) -> BundlingItem:
    item = await db.get(BundlingItem, bundling_id)
    if item is None or item.bundling_produk_id != produk_id or item.deleted_at is not None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Item bundling tidak ditemukan")
    return item


@router.patch(
    "/produk/{produk_id}/bundling/{bundling_id}", response_model=BundlingItemOut,
    dependencies=[Depends(require_fitur("bundling"))],
)
async def ubah_bundling(
    produk_id: uuid.UUID,
    bundling_id: uuid.UUID,
    body: BundlingItemUpdateIn,
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> BundlingItemOut:
    await _wajib_izin_produk_kelola(db, role_id)
    await ambil_produk_milik_toko(produk_id, toko_id, db)
    item = await _ambil_bundling_milik_produk(db, bundling_id, produk_id)

    perubahan = body.model_dump(exclude_unset=True)
    if "varian_id" in perubahan:
        await _pastikan_varian_milik_produk(db, perubahan["varian_id"], item.produk_id)
    data_lama = {k: str(getattr(item, k)) for k in perubahan}
    for field, value in perubahan.items():
        setattr(item, field, value)
    isi = await ambil_produk_milik_toko(item.produk_id, toko_id, db)
    await catat_audit(
        db, toko_id=toko_id, pengguna_id=pengguna_id, aksi="ubah_bundling",
        tabel="bundling_item", record_id=item.id,
        data_lama=data_lama, data_baru={k: str(v) for k, v in perubahan.items()},
    )
    await db.commit()
    await db.refresh(item)
    return BundlingItemOut(
        id=item.id, bundling_produk_id=item.bundling_produk_id, produk_id=item.produk_id, nama_produk=isi.nama,
        varian_id=item.varian_id, qty=item.qty,
    )


@router.delete(
    "/produk/{produk_id}/bundling/{bundling_id}", status_code=status.HTTP_204_NO_CONTENT,
    dependencies=[Depends(require_fitur("bundling"))],
)
async def hapus_bundling(
    produk_id: uuid.UUID,
    bundling_id: uuid.UUID,
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> None:
    await _wajib_izin_produk_kelola(db, role_id)
    await ambil_produk_milik_toko(produk_id, toko_id, db)
    item = await _ambil_bundling_milik_produk(db, bundling_id, produk_id)
    item.deleted_at = datetime.now(UTC)
    await catat_audit(
        db, toko_id=toko_id, pengguna_id=pengguna_id, aksi="hapus_bundling",
        tabel="bundling_item", record_id=item.id, data_lama={"produk_id": str(item.produk_id)},
    )
    await db.commit()


# --------------------------------------------------------- Harga grosir --

@router.get(
    "/produk/{produk_id}/harga-grosir", response_model=list[HargaGrosirOut],
    dependencies=[Depends(require_fitur("harga_grosir"))],
)
async def daftar_harga_grosir(
    produk_id: uuid.UUID, toko_id: uuid.UUID = Depends(get_toko_id), db: AsyncSession = Depends(get_db)
) -> list[HargaGrosir]:
    await ambil_produk_milik_toko(produk_id, toko_id, db)
    rows = (
        await db.execute(
            select(HargaGrosir).where(HargaGrosir.produk_id == produk_id, HargaGrosir.deleted_at.is_(None))
        )
    ).scalars().all()
    return list(rows)


@router.post(
    "/produk/{produk_id}/harga-grosir", response_model=HargaGrosirOut, status_code=status.HTTP_201_CREATED,
    dependencies=[Depends(require_fitur("harga_grosir"))],
)
async def tambah_harga_grosir(
    produk_id: uuid.UUID,
    body: HargaGrosirIn,
    toko_id: uuid.UUID = Depends(get_toko_id),
    db: AsyncSession = Depends(get_db),
) -> HargaGrosir:
    await ambil_produk_milik_toko(produk_id, toko_id, db)
    await _pastikan_varian_milik_produk(db, body.varian_id, produk_id)
    if body.outlet_id is not None:
        outlet = await db.get(Outlet, body.outlet_id)
        if outlet is None or outlet.toko_id != toko_id:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Outlet tidak ditemukan")

    harga = HargaGrosir(produk_id=produk_id, **body.model_dump())
    db.add(harga)
    await db.commit()
    await db.refresh(harga)
    return harga


async def _ambil_harga_grosir_milik_produk(
    db: AsyncSession, harga_grosir_id: uuid.UUID, produk_id: uuid.UUID
) -> HargaGrosir:
    harga = await db.get(HargaGrosir, harga_grosir_id)
    if harga is None or harga.produk_id != produk_id or harga.deleted_at is not None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Harga grosir tidak ditemukan")
    return harga


@router.patch(
    "/produk/{produk_id}/harga-grosir/{harga_grosir_id}", response_model=HargaGrosirOut,
    dependencies=[Depends(require_fitur("harga_grosir"))],
)
async def ubah_harga_grosir(
    produk_id: uuid.UUID,
    harga_grosir_id: uuid.UUID,
    body: HargaGrosirUpdateIn,
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> HargaGrosir:
    await _wajib_izin_produk_kelola(db, role_id)
    await ambil_produk_milik_toko(produk_id, toko_id, db)
    harga = await _ambil_harga_grosir_milik_produk(db, harga_grosir_id, produk_id)

    perubahan = body.model_dump(exclude_unset=True)
    data_lama = {k: str(getattr(harga, k)) for k in perubahan}
    for field, value in perubahan.items():
        setattr(harga, field, value)
    await catat_audit(
        db, toko_id=toko_id, pengguna_id=pengguna_id, aksi="ubah_harga_grosir",
        tabel="harga_grosir", record_id=harga.id,
        data_lama=data_lama, data_baru={k: str(v) for k, v in perubahan.items()},
    )
    await db.commit()
    await db.refresh(harga)
    return harga


@router.delete(
    "/produk/{produk_id}/harga-grosir/{harga_grosir_id}", status_code=status.HTTP_204_NO_CONTENT,
    dependencies=[Depends(require_fitur("harga_grosir"))],
)
async def hapus_harga_grosir(
    produk_id: uuid.UUID,
    harga_grosir_id: uuid.UUID,
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> None:
    await _wajib_izin_produk_kelola(db, role_id)
    await ambil_produk_milik_toko(produk_id, toko_id, db)
    harga = await _ambil_harga_grosir_milik_produk(db, harga_grosir_id, produk_id)
    harga.deleted_at = datetime.now(UTC)
    await catat_audit(
        db, toko_id=toko_id, pengguna_id=pengguna_id, aksi="hapus_harga_grosir",
        tabel="harga_grosir", record_id=harga.id, data_lama={"min_qty": str(harga.min_qty)},
    )
    await db.commit()


# --------------------------------------------------------- Harga outlet --

@router.get("/produk/{produk_id}/harga-outlet", response_model=list[HargaOutletOut])
async def daftar_harga_outlet(
    produk_id: uuid.UUID, toko_id: uuid.UUID = Depends(get_toko_id), db: AsyncSession = Depends(get_db)
) -> list[HargaOutlet]:
    await ambil_produk_milik_toko(produk_id, toko_id, db)
    rows = (
        await db.execute(
            select(HargaOutlet).where(HargaOutlet.produk_id == produk_id, HargaOutlet.deleted_at.is_(None))
        )
    ).scalars().all()
    return list(rows)


@router.post(
    "/produk/{produk_id}/harga-outlet", response_model=HargaOutletOut, status_code=status.HTTP_201_CREATED
)
async def tambah_harga_outlet(
    produk_id: uuid.UUID,
    body: HargaOutletIn,
    toko_id: uuid.UUID = Depends(get_toko_id),
    db: AsyncSession = Depends(get_db),
) -> HargaOutlet:
    await ambil_produk_milik_toko(produk_id, toko_id, db)
    outlet = await db.get(Outlet, body.outlet_id)
    if outlet is None or outlet.toko_id != toko_id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Outlet tidak ditemukan")
    await _pastikan_varian_milik_produk(db, body.varian_id, produk_id)

    harga = HargaOutlet(produk_id=produk_id, **body.model_dump())
    db.add(harga)
    await db.commit()
    await db.refresh(harga)
    return harga


async def _ambil_harga_outlet_milik_produk(
    db: AsyncSession, harga_outlet_id: uuid.UUID, produk_id: uuid.UUID
) -> HargaOutlet:
    harga = await db.get(HargaOutlet, harga_outlet_id)
    if harga is None or harga.produk_id != produk_id or harga.deleted_at is not None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Harga outlet tidak ditemukan")
    return harga


@router.patch("/produk/{produk_id}/harga-outlet/{harga_outlet_id}", response_model=HargaOutletOut)
async def ubah_harga_outlet(
    produk_id: uuid.UUID,
    harga_outlet_id: uuid.UUID,
    body: HargaOutletUpdateIn,
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> HargaOutlet:
    await _wajib_izin_produk_kelola(db, role_id)
    await ambil_produk_milik_toko(produk_id, toko_id, db)
    harga = await _ambil_harga_outlet_milik_produk(db, harga_outlet_id, produk_id)

    perubahan = body.model_dump(exclude_unset=True)
    data_lama = {k: str(getattr(harga, k)) for k in perubahan}
    for field, value in perubahan.items():
        setattr(harga, field, value)
    await catat_audit(
        db, toko_id=toko_id, pengguna_id=pengguna_id, aksi="ubah_harga_outlet",
        tabel="harga_outlet", record_id=harga.id,
        data_lama=data_lama, data_baru={k: str(v) for k, v in perubahan.items()},
    )
    await db.commit()
    await db.refresh(harga)
    return harga


@router.delete("/produk/{produk_id}/harga-outlet/{harga_outlet_id}", status_code=status.HTTP_204_NO_CONTENT)
async def hapus_harga_outlet(
    produk_id: uuid.UUID,
    harga_outlet_id: uuid.UUID,
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> None:
    await _wajib_izin_produk_kelola(db, role_id)
    await ambil_produk_milik_toko(produk_id, toko_id, db)
    harga = await _ambil_harga_outlet_milik_produk(db, harga_outlet_id, produk_id)
    harga.deleted_at = datetime.now(UTC)
    await catat_audit(
        db, toko_id=toko_id, pengguna_id=pengguna_id, aksi="hapus_harga_outlet",
        tabel="harga_outlet", record_id=harga.id, data_lama={"outlet_id": str(harga.outlet_id)},
    )
    await db.commit()


# --------------------------------------------------------- Produk pajak --
# Tahap 5 B.4 - override pajak per produk (gate 'pajak_per_produk').
# Link murni (produk_id+pajak_id, tanpa deleted_at - lihat model), jadi
# hapus = hard delete barisnya, bukan soft delete.


@router.get(
    "/produk/{produk_id}/pajak", response_model=list[ProdukPajakOut],
    dependencies=[Depends(require_fitur("pajak_per_produk"))],
)
async def daftar_produk_pajak(
    produk_id: uuid.UUID, toko_id: uuid.UUID = Depends(get_toko_id), db: AsyncSession = Depends(get_db)
) -> list[ProdukPajakOut]:
    await ambil_produk_milik_toko(produk_id, toko_id, db)
    rows = (
        await db.execute(
            select(ProdukPajak, Pajak).join(Pajak, Pajak.id == ProdukPajak.pajak_id).where(ProdukPajak.produk_id == produk_id)
        )
    ).all()
    return [
        ProdukPajakOut(produk_id=pp.produk_id, pajak_id=pp.pajak_id, nama_pajak=pajak.nama) for pp, pajak in rows
    ]


@router.post(
    "/produk/{produk_id}/pajak/{pajak_id}", status_code=status.HTTP_204_NO_CONTENT,
    dependencies=[Depends(require_fitur("pajak_per_produk"))],
)
async def tautkan_produk_pajak(
    produk_id: uuid.UUID,
    pajak_id: uuid.UUID,
    toko_id: uuid.UUID = Depends(get_toko_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> None:
    """Idempoten (sama pola dgn PUT .../grup-modifier/{id}) - panggil ulang
    utk pajak yang sudah tertaut tidak error/dobel baris."""
    await _wajib_izin_produk_kelola(db, role_id)
    await ambil_produk_milik_toko(produk_id, toko_id, db)
    pajak = await db.get(Pajak, pajak_id)
    if pajak is None or pajak.toko_id != toko_id or pajak.deleted_at is not None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Pajak tidak ditemukan")

    existing = await db.get(ProdukPajak, {"produk_id": produk_id, "pajak_id": pajak_id})
    if existing is None:
        db.add(ProdukPajak(produk_id=produk_id, pajak_id=pajak_id))
        await db.commit()


@router.delete(
    "/produk/{produk_id}/pajak/{pajak_id}", status_code=status.HTTP_204_NO_CONTENT,
    dependencies=[Depends(require_fitur("pajak_per_produk"))],
)
async def lepas_produk_pajak(
    produk_id: uuid.UUID,
    pajak_id: uuid.UUID,
    toko_id: uuid.UUID = Depends(get_toko_id),
    pengguna_id: uuid.UUID = Depends(get_pengguna_id),
    role_id: uuid.UUID = Depends(get_role_id),
    db: AsyncSession = Depends(get_db),
) -> None:
    await _wajib_izin_produk_kelola(db, role_id)
    await ambil_produk_milik_toko(produk_id, toko_id, db)
    link = await db.get(ProdukPajak, {"produk_id": produk_id, "pajak_id": pajak_id})
    if link is None:
        return  # idempotent - sudah terlepas sebelumnya
    await catat_audit(
        db, toko_id=toko_id, pengguna_id=pengguna_id, aksi="lepas_produk_pajak",
        tabel="produk_pajak", record_id=produk_id, data_lama={"pajak_id": str(pajak_id)},
    )
    await db.delete(link)
    await db.commit()
