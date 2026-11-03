"""Kuota jumlah outlet per toko - dipisah dari gating fitur (`multi_outlet`
di fitur_service.py) krn ini soal BERAPA BANYAK outlet yang sudah DIBAYAR
(langganan.jumlah_outlet), bukan soal BOLEH/TIDAK punya >1 outlet sama
sekali (itu urusan fitur `multi_outlet`) - toko Pro/Bisnis yang fiturnya
sudah terbuka TETAP bisa kena batas ini kalau langganannya cuma bayar utk
mis. 2 outlet tapi coba buat outlet ke-3."""

import uuid

from fastapi import HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.services.fitur_service import langganan_aktif_toko, paket_efektif


async def pastikan_kuota_outlet(db: AsyncSession, *, toko_id: uuid.UUID, jumlah_sekarang: int) -> None:
    # Temuan#3 (rapikan F3) - FIX: sebelumnya baris ini query Langganan
    # langsung by status='aktif' SAJA (tidak cek `berakhir`), jadi
    # langganan yang SUDAH lewat tanggal berakhir tapi belum
    # di-cron-update statusnya tetap dipakai jumlah_outlet-nya (kuota
    # lama yang sudah dibayar, bukan kuota Gratis) - beda dgn
    # paket_efektif yang SELALU cek `berakhir`. Sekarang pakai
    # langganan_aktif_toko yang SAMA definisi "aktif"-nya dgn paket_efektif,
    # supaya outlet ikut turun ke kuota Gratis begitu langganan kedaluwarsa,
    # persis seperti kuota pengguna/produk.
    langganan = await langganan_aktif_toko(db, toko_id)

    if langganan is not None:
        batas: int | None = langganan.jumlah_outlet
    else:
        paket = await paket_efektif(db, toko_id)
        batas = paket.maks_outlet

    if batas is not None and jumlah_sekarang + 1 > batas:
        raise HTTPException(
            status.HTTP_403_FORBIDDEN,
            detail={"kode": "kuota_habis", "jenis": "outlet", "batas": batas},
        )
