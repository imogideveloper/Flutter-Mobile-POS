"""F3.F - halaman "Paket langganan": paket aktif+masa berlaku+pemakaian
kuota, tabel perbandingan fitur per paket (dari data paket/paket_fitur
sungguhan), dan permintaan upgrade (TANPA pembayaran di dalam app - lihat
schemas/langganan.py). Aktivasi SUNGGUHAN hanya lewat endpoint admin
terpisah (app/core/admin_auth.py), bukan dari sini."""

import uuid
from datetime import UTC, datetime
from decimal import Decimal

from fastapi import HTTPException, status
from sqlalchemy import func, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.akun import Pengguna
from app.models.fitur import Fitur, PaketFitur
from app.models.outlet import Langganan, Outlet, Paket, PermintaanUpgrade
from app.models.produk import Produk
from app.schemas.langganan import (
    AdminAktivasiLangganan,
    LanggananSayaOut,
    PaketOut,
    PemakaianOut,
    PermintaanUpgradeIn,
)
from app.services.fitur_service import paket_efektif, trial_toko
from app.services.platform_service import (
    DEFAULT_TRIAL_NOTIFIKASI_HARI,
    KUNCI_TRIAL_NOTIFIKASI_HARI,
    ambil_int,
)


async def daftar_paket(db: AsyncSession) -> list[PaketOut]:
    paket_rows = (
        await db.execute(select(Paket).where(Paket.aktif.is_(True)).order_by(Paket.urutan))
    ).scalars().all()

    hasil = []
    for paket in paket_rows:
        kode_fitur = (
            await db.execute(
                select(Fitur.kode).join(PaketFitur, PaketFitur.fitur_id == Fitur.id).where(
                    PaketFitur.paket_id == paket.id
                )
            )
        ).scalars().all()
        hasil.append(
            PaketOut(
                id=paket.id,
                nama=paket.nama,
                urutan=paket.urutan,
                harga_bulanan=Decimal(str(paket.harga_bulanan)),
                harga_tahunan=Decimal(str(paket.harga_tahunan)) if paket.harga_tahunan is not None else None,
                maks_outlet=paket.maks_outlet,
                maks_pengguna=paket.maks_pengguna,
                maks_produk=paket.maks_produk,
                kode_fitur=sorted(kode_fitur),
            )
        )
    return hasil


async def langganan_saya(db: AsyncSession, toko_id: uuid.UUID) -> LanggananSayaOut:
    langganan = (
        await db.execute(
            select(Langganan)
            .where(Langganan.toko_id == toko_id, Langganan.status.in_(("aktif", "trial")))
            .order_by(Langganan.created_at.desc())
        )
    ).scalars().first()
    if langganan is None:
        # Fallback (seharusnya tidak pernah terjadi - setiap toko dapat
        # Langganan Gratis saat registrasi) - ambil yang PALING BARU apa
        # pun statusnya, drpd 500 ke app.
        langganan = (
            await db.execute(
                select(Langganan).where(Langganan.toko_id == toko_id).order_by(Langganan.created_at.desc())
            )
        ).scalars().first()
    paket = await db.get(Paket, langganan.paket_id)

    jumlah_outlet = (
        await db.scalar(
            select(func.count()).select_from(Outlet).where(Outlet.toko_id == toko_id, Outlet.deleted_at.is_(None))
        )
    ) or 0
    jumlah_pengguna = (
        await db.scalar(
            select(func.count()).select_from(Pengguna).where(
                Pengguna.toko_id == toko_id, Pengguna.deleted_at.is_(None), Pengguna.aktif.is_(True)
            )
        )
    ) or 0
    jumlah_produk = (
        await db.scalar(
            select(func.count()).select_from(Produk).where(
                Produk.toko_id == toko_id, Produk.deleted_at.is_(None), Produk.aktif.is_(True)
            )
        )
    ) or 0

    trial = await trial_toko(db, toko_id)
    efektif = await paket_efektif(db, toko_id)
    notif_hari = await ambil_int(db, KUNCI_TRIAL_NOTIFIKASI_HARI, DEFAULT_TRIAL_NOTIFIKASI_HARI)

    return LanggananSayaOut(
        paket_id=paket.id,
        paket_nama=paket.nama,
        status=langganan.status,
        periode=langganan.periode,
        jumlah_outlet=langganan.jumlah_outlet,
        mulai=langganan.mulai,
        berakhir=langganan.berakhir,
        pemakaian=PemakaianOut(outlet=jumlah_outlet, pengguna=jumlah_pengguna, produk=jumlah_produk),
        paket_efektif_nama=efektif.nama,
        trial_aktif=bool(trial and trial.aktif),
        trial_mulai=trial.mulai if trial else None,
        trial_berakhir=trial.berakhir if trial else None,
        trial_durasi_bulan=trial.durasi_bulan if trial else None,
        trial_hari_tersisa=trial.hari_tersisa if trial else None,
        trial_notifikasi_hari=notif_hari,
    )


async def buat_permintaan_upgrade(
    db: AsyncSession, *, toko_id: uuid.UUID, body: PermintaanUpgradeIn
) -> PermintaanUpgrade:
    paket_tujuan = await db.get(Paket, body.paket_tujuan_id)
    if paket_tujuan is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Paket tujuan tidak ditemukan")

    permintaan = PermintaanUpgrade(
        toko_id=toko_id,
        paket_tujuan_id=body.paket_tujuan_id,
        jumlah_outlet=body.jumlah_outlet,
        periode=body.periode,
        catatan=body.catatan,
    )
    db.add(permintaan)
    await db.commit()
    await db.refresh(permintaan)
    return permintaan


async def admin_aktivasi_langganan(db: AsyncSession, body: AdminAktivasiLangganan) -> Langganan:
    """F3.F.3/F3.F.4 - aktivasi SUNGGUHAN, dilindungi admin_auth (bukan
    izin role toko). Membuat baris Langganan BARU (bukan update yang lama
    - riwayat langganan toko tetap utuh), sync berikutnya (sync_service.py
    sudah baca via paket_efektif) otomatis membawa FeatureGate baru ke HP.

    Langganan 'aktif'/'trial' toko ini yang LAMA ditandai 'batal' dulu -
    toko cuma boleh punya SATU langganan efektif pada satu waktu. Tanpa
    ini, `langganan_saya()`/`paket_efektif()` (keduanya urut by
    created_at) bisa salah pilih baris kalau dua Langganan dibuat dalam
    resolusi waktu yang sama (nyata kejadian di SQLite test - func.now()
    per detik, bukan cuma risiko teori)."""
    await db.execute(
        update(Langganan)
        .where(Langganan.toko_id == body.toko_id, Langganan.status.in_(("aktif", "trial")))
        .values(status="batal")
    )

    langganan = Langganan(
        toko_id=body.toko_id,
        paket_id=body.paket_id,
        jumlah_outlet=body.jumlah_outlet,
        periode=body.periode,
        mulai=datetime.now(UTC),
        berakhir=body.berakhir,
        status="aktif",
    )
    db.add(langganan)
    await db.commit()
    await db.refresh(langganan)
    return langganan
