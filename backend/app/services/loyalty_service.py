"""Poin loyalitas pelanggan (modul 10 - level_member, aturan_poin,
riwayat_poin). Dipanggil dari checkout_service (dapat poin), void_service
(batalkan SELURUH poin transaksi itu) dan refund_service (batalkan poin
PROPORSIONAL ke nilai refund) - supaya `pelanggan.poin`/`total_belanja`
selalu konsisten dgn transaksi yang benar2 final (bukan yang di-void/
di-refund).

SENGAJA tidak melempar error kalau aturan_poin toko belum diatur/tidak
aktif - itu kondisi normal (banyak toko retail kecil tidak pakai member),
bukan kegagalan."""

import uuid
from decimal import ROUND_DOWN, ROUND_HALF_UP, Decimal

from fastapi import HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.pelanggan import AturanPoin, LevelMember, Pelanggan, RiwayatPoin


async def _ambil_aturan_aktif(db: AsyncSession, toko_id: uuid.UUID) -> AturanPoin | None:
    """Khusus jalur DAPAT poin (earning) - nonaktif kalau nominal_per_poin
    tidak masuk akal. JANGAN dipakai utk jalur TUKAR poin (redemption) -
    toko yang sengaja hanya mau "poin sbg perk" (nilai_tukar_poin=0) tapi
    tetap kasih poin (nominal_per_poin>0) itu valid, begitu juga
    sebaliknya - dua kegunaan tidak boleh saling mengunci, lihat
    _ambil_aturan_untuk_tukar."""
    aturan = await db.get(AturanPoin, toko_id)
    if aturan is None or not aturan.aktif or aturan.nominal_per_poin <= 0:
        return None
    return aturan


async def _ambil_aturan_untuk_tukar(db: AsyncSession, toko_id: uuid.UUID) -> AturanPoin | None:
    """Khusus jalur TUKAR poin (redemption) - lihat catatan di
    _ambil_aturan_aktif soal kenapa ini terpisah (nominal_per_poin tidak
    relevan di sini)."""
    aturan = await db.get(AturanPoin, toko_id)
    if aturan is None or not aturan.aktif or aturan.nilai_tukar_poin <= 0:
        return None
    return aturan


async def tambah_poin_dari_transaksi(
    db: AsyncSession, *, toko_id: uuid.UUID, pelanggan_id: uuid.UUID | None, transaksi_id: uuid.UUID, total: Decimal
) -> None:
    if pelanggan_id is None:
        return

    aturan = await _ambil_aturan_aktif(db, toko_id)
    if aturan is None:
        return

    pelanggan = await db.get(Pelanggan, pelanggan_id)
    if pelanggan is None:
        return

    pengali = Decimal("1")
    if pelanggan.level_member_id is not None:
        level = await db.get(LevelMember, pelanggan.level_member_id)
        if level is not None:
            pengali = Decimal(str(level.pengali_poin))

    poin_dasar = int((total / aturan.nominal_per_poin).to_integral_value(rounding=ROUND_DOWN))
    poin_didapat = int((Decimal(poin_dasar) * pengali).to_integral_value(rounding=ROUND_HALF_UP))
    if poin_didapat <= 0:
        return

    pelanggan.poin += poin_didapat
    pelanggan.total_belanja += total

    db.add(
        RiwayatPoin(
            pelanggan_id=pelanggan_id,
            transaksi_id=transaksi_id,
            poin=poin_didapat,
            keterangan="Poin dari transaksi",
        )
    )


async def batalkan_poin_transaksi(db: AsyncSession, *, pelanggan_id: uuid.UUID | None, transaksi_id: uuid.UUID, total: Decimal) -> None:
    """Dipanggil saat VOID (transaksi batal total) - balikkan SELURUH poin
    yang pernah didapat dari transaksi ini + kurangi total_belanja penuh."""

    if pelanggan_id is None:
        return

    poin_awal = await _total_poin_didapat(db, transaksi_id)
    if poin_awal == 0 and total == 0:
        return

    pelanggan = await db.get(Pelanggan, pelanggan_id)
    if pelanggan is None:
        return

    pelanggan.poin = max(0, pelanggan.poin - poin_awal)
    pelanggan.total_belanja = max(Decimal("0"), pelanggan.total_belanja - total)

    if poin_awal != 0:
        db.add(
            RiwayatPoin(
                pelanggan_id=pelanggan_id,
                transaksi_id=transaksi_id,
                poin=-poin_awal,
                keterangan="Pembatalan poin (transaksi di-void)",
            )
        )


async def kurangi_poin_proporsional(
    db: AsyncSession,
    *,
    pelanggan_id: uuid.UUID | None,
    transaksi_id: uuid.UUID,
    total_transaksi: Decimal,
    jumlah_refund: Decimal,
) -> None:
    """Dipanggil saat REFUND (sebagian/penuh) - poin & total_belanja
    dikurangi PROPORSIONAL terhadap porsi yang di-refund, bukan dibatalkan
    total (beda dgn void, yang membatalkan semuanya karena transaksinya
    memang batal total)."""

    if pelanggan_id is None or total_transaksi <= 0 or jumlah_refund <= 0:
        return

    poin_awal = await _total_poin_didapat(db, transaksi_id)
    if poin_awal == 0:
        pelanggan = await db.get(Pelanggan, pelanggan_id)
        if pelanggan is not None:
            pelanggan.total_belanja = max(Decimal("0"), pelanggan.total_belanja - jumlah_refund)
        return

    porsi = min(Decimal("1"), jumlah_refund / total_transaksi)
    poin_dikurangi = int((Decimal(poin_awal) * porsi).to_integral_value(rounding=ROUND_HALF_UP))
    if poin_dikurangi <= 0:
        return

    pelanggan = await db.get(Pelanggan, pelanggan_id)
    if pelanggan is None:
        return

    pelanggan.poin = max(0, pelanggan.poin - poin_dikurangi)
    pelanggan.total_belanja = max(Decimal("0"), pelanggan.total_belanja - jumlah_refund)

    db.add(
        RiwayatPoin(
            pelanggan_id=pelanggan_id,
            transaksi_id=transaksi_id,
            poin=-poin_dikurangi,
            keterangan="Pengurangan poin (refund sebagian/penuh)",
        )
    )


async def hitung_dan_validasi_tukar_poin(
    db: AsyncSession,
    *,
    toko_id: uuid.UUID,
    pelanggan_id: uuid.UUID | None,
    poin_ditukar: int,
    total_tersedia: Decimal,
) -> Decimal:
    """Hitung nilai diskon (Rupiah) dari `poin_ditukar` + validasi aturan -
    HANYA dipakai checkout ONLINE (server adalah sumber kebenaran, belum
    ada uang/barang keluar, jadi aman menolak 400 kalau tidak sah). Push
    offline TIDAK memanggil ini sama sekali - lihat `CheckoutIn.
    diskon_poin_klien` (dipercaya apa adanya, pola *_klien yang sama dgn
    field lain, C.2).

    Dibalas 0 (tanpa menyentuh DB sama sekali) kalau poin_ditukar<=0."""
    if poin_ditukar <= 0:
        return Decimal("0")

    if pelanggan_id is None:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Tukar poin wajib memilih pelanggan")

    aturan = await _ambil_aturan_untuk_tukar(db, toko_id)
    if aturan is None:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Penukaran poin tidak aktif utk toko ini")

    if aturan.min_tukar_poin > 0 and poin_ditukar < aturan.min_tukar_poin:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST, f"Minimal tukar poin adalah {aturan.min_tukar_poin}"
        )

    pelanggan = await db.get(Pelanggan, pelanggan_id)
    if pelanggan is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Pelanggan tidak ditemukan")

    if pelanggan.poin < poin_ditukar:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Poin pelanggan tidak cukup")

    nilai = Decimal(poin_ditukar) * Decimal(str(aturan.nilai_tukar_poin))
    return min(nilai, total_tersedia)


async def tukar_poin_untuk_diskon(
    db: AsyncSession, *, pelanggan_id: uuid.UUID, transaksi_id: uuid.UUID, poin_ditukar: int
) -> None:
    """Dipanggil SETELAH baris Transaksi sudah di-flush (butuh transaksi_id
    valid utk FK RiwayatPoin) - kurangi poin pelanggan (clamp ke 0, lihat
    docstring hitung_dan_validasi_tukar_poin) + catat riwayat negatif."""
    pelanggan = await db.get(Pelanggan, pelanggan_id)
    if pelanggan is None:
        return
    pelanggan.poin = max(0, pelanggan.poin - poin_ditukar)
    db.add(
        RiwayatPoin(
            pelanggan_id=pelanggan_id,
            transaksi_id=transaksi_id,
            poin=-poin_ditukar,
            keterangan="Poin ditukar untuk diskon checkout",
        )
    )


async def kembalikan_poin_ditukar(
    db: AsyncSession, *, pelanggan_id: uuid.UUID | None, transaksi_id: uuid.UUID
) -> None:
    """Dipanggil saat VOID - transaksi batal TOTAL, jadi poin yang sempat
    ditukar pelanggan utk diskon transaksi ini (lihat tukar_poin_untuk_
    diskon) wajib dikembalikan PENUH, bukan cuma poin yang DIDAPAT
    (batalkan_poin_transaksi) yang dibalikkan.

    BELUM ditangani utk REFUND sebagian/penuh (beda dari batalkan poin
    DIDAPAT yang sudah proporsional lewat kurangi_poin_proporsional) -
    diakui sbg keterbatasan, bukan ditutupi: mengembalikan poin ditukar
    secara proporsional ke refund itu ambigu (apakah refund sebagian
    barang harus "membatalkan" sebagian penukaran poin juga?) dan belum
    diputuskan aturannya."""
    if pelanggan_id is None:
        return

    poin_ditukar = await db.scalar(
        select(func.coalesce(func.sum(RiwayatPoin.poin), 0)).where(
            RiwayatPoin.transaksi_id == transaksi_id, RiwayatPoin.poin < 0,
            RiwayatPoin.keterangan == "Poin ditukar untuk diskon checkout",
        )
    )
    poin_ditukar = abs(int(poin_ditukar or 0))
    if poin_ditukar == 0:
        return

    pelanggan = await db.get(Pelanggan, pelanggan_id)
    if pelanggan is None:
        return

    pelanggan.poin += poin_ditukar
    db.add(
        RiwayatPoin(
            pelanggan_id=pelanggan_id,
            transaksi_id=transaksi_id,
            poin=poin_ditukar,
            keterangan="Pengembalian poin ditukar (transaksi di-void)",
        )
    )


async def _total_poin_didapat(db: AsyncSession, transaksi_id: uuid.UUID) -> int:
    """Jumlah poin POSITIF (bukan pengurangan dari refund/void
    sebelumnya) yang pernah dicatat utk transaksi ini - dasar perhitungan
    void (batalkan semua) & refund (batalkan proporsional)."""

    total = await db.scalar(
        select(func.coalesce(func.sum(RiwayatPoin.poin), 0)).where(
            RiwayatPoin.transaksi_id == transaksi_id, RiwayatPoin.poin > 0
        )
    )
    return int(total or 0)
