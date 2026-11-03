"""Cicilan/pelunasan kasbon (tahap 3b-1 aturan #2-3) - dipanggil dari
POST /transaksi/{id}/pembayaran (online, real-time) DAN dari /sync/push
(pembayaran yang dibuat offline di HP, dikirim belakangan). Idempotent
lewat `PembayaranIn.id` (UUID dari HP) - pola sama dgn `CheckoutIn.id`.

Overpay offline (aturan #3): kalau dua HP sama-sama mencatat pelunasan
offline sehingga totalnya melebihi sisa_tagihan, KEDUANYA tetap diterima
apa adanya (uangnya sudah benar2 diterima kasir, tidak bisa "dibatalkan"
dgn menolak push) - `sisa_tagihan` cuma diklem ke 0, selisihnya dicatat
sbg 'lebih bayar' di audit_log + notifikasi owner utk diperiksa manual,
bukan ditolak."""

import uuid
from decimal import Decimal

from fastapi import HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.audit import AuditLog, Notifikasi
from app.models.transaksi import MetodeBayar, Pembayaran, Transaksi
from app.schemas.pembayaran import PembayaranIn
from app.services.kepemilikan import get_shift_aktif

_DUA_DESIMAL = Decimal("0.01")


def _m(nilai: Decimal) -> Decimal:
    return nilai.quantize(_DUA_DESIMAL)


async def catat_pembayaran(
    db: AsyncSession, *, toko_id: uuid.UUID, transaksi: Transaksi, body: PembayaranIn
) -> Pembayaran:
    if body.id is not None:
        existing = await db.get(Pembayaran, body.id)
        if existing is not None:
            return existing

    if body.jumlah <= 0:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Jumlah pembayaran harus lebih dari 0")
    if transaksi.status != "selesai":
        raise HTTPException(
            status.HTTP_409_CONFLICT, "Hanya transaksi 'selesai' yang bisa dicicil/dilunasi"
        )

    metode = await db.get(MetodeBayar, body.metode_bayar_id)
    if metode is None or metode.toko_id != toko_id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Metode bayar tidak ditemukan")

    # Shift PENERIMA uang ini (boleh beda dari shift transaksi aslinya -
    # lihat shift_service.py) - tetap wajib aktif & milik outlet transaksi
    # ini, sama pola validasi dgn checkout_service._validasi_kepemilikan.
    await get_shift_aktif(db, body.shift_id, toko_id, transaksi.outlet_id)

    jumlah = _m(Decimal(str(body.jumlah)))
    sisa_sebelum = Decimal(str(transaksi.sisa_tagihan or 0))
    lebih_bayar = max(Decimal("0"), jumlah - sisa_sebelum)
    sisa_baru = _m(max(Decimal("0"), sisa_sebelum - jumlah))
    jenis = "pelunasan" if sisa_baru == 0 else "cicilan"

    kwargs = {} if body.id is None else {"id": body.id}
    pembayaran = Pembayaran(
        **kwargs,
        transaksi_id=transaksi.id,
        shift_id=body.shift_id,
        metode_bayar_id=body.metode_bayar_id,
        jumlah=jumlah,
        jenis=jenis,
        status="berhasil",
        payload_gateway=body.payload_gateway,
        dibayar_pada=body.dibayar_pada,
    )
    db.add(pembayaran)

    transaksi.sisa_tagihan = sisa_baru
    transaksi.status_bayar = "lunas" if sisa_baru == 0 else "sebagian"

    if lebih_bayar > 0:
        db.add(
            AuditLog(
                toko_id=toko_id, aksi="pembayaran_lebih_bayar", tabel="transaksi", record_id=transaksi.id,
                data_lama={"sisa_tagihan_sebelum": str(sisa_sebelum)},
                data_baru={"jumlah_dibayar": str(jumlah), "lebih_bayar": str(lebih_bayar)},
            )
        )
        db.add(
            Notifikasi(
                toko_id=toko_id, jenis="pembayaran_lebih_bayar",
                judul="Pembayaran kasbon melebihi sisa tagihan",
                isi=(
                    f"Transaksi {transaksi.nomor_struk} menerima pembayaran {jumlah} padahal sisa "
                    f"tagihan cuma {sisa_sebelum} (lebih {lebih_bayar}) - kemungkinan dicatat dobel "
                    "dari 2 HP offline yang sama-sama melunasi. Uang tetap dianggap diterima, mohon "
                    "diperiksa manual."
                ),
                ref_tipe="transaksi", ref_id=transaksi.id,
            )
        )

    await db.commit()
    await db.refresh(pembayaran)
    return pembayaran
