"""F3.E - "Simpan pesanan" (open bill), versi pertama SENGAJA per-HP:
pesanan tersimpan HANYA bisa dibuka/dilanjutkan/dibayar di HP yang sama
yang membuatnya (keranjang + metadata-nya cuma ada di drift lokal HP itu).
Endpoint ini murni CADANGAN/backup (dipakai utk rekonstruksi manual kalau
HP hilang/rusak, dokumen #F3.E.4) - BUKAN sumber kebenaran yang bisa
dibuka dari HP lain, dan TIDAK PERNAH memotong stok/membuat baris
pembayaran/menyentuh kasbon. Saat kasir benar2 membayar pesanan ini,
device memanggil endpoint checkout biasa (POST /transaksi) dgn id BARU -
baris cadangan ini lalu dihapus lewat hapus_pesanan_tersimpan (bukan
di-upgrade in-place, lebih sederhana & tidak menyentuh logika checkout_service
yang sudah kompleks & teruji)."""

import uuid
from decimal import ROUND_HALF_UP, Decimal

from fastapi import HTTPException, status
from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.models.akun import Pengguna
from app.models.audit import AuditLog
from app.models.transaksi import ItemTransaksi, Transaksi
from app.schemas.pesanan_tersimpan import PesananTersimpanIn
from app.services.identitas_service import validasi_dan_tandai
from app.services.izin_service import has_izin
from app.services.kepemilikan import get_outlet_milik_toko


def _bulatkan(nilai: Decimal) -> Decimal:
    return nilai.quantize(Decimal("1"), rounding=ROUND_HALF_UP)


async def simpan_pesanan_cadangan(
    db: AsyncSession, *, toko_id: uuid.UUID, pengguna_id: uuid.UUID, body: PesananTersimpanIn
) -> Transaksi:
    await get_outlet_milik_toko(db, body.outlet_id, toko_id)
    if not body.items:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Minimal satu item harus diisi")

    subtotal = sum((_bulatkan(i.qty * i.harga_satuan) for i in body.items), Decimal("0"))

    existing = await db.get(Transaksi, body.id)
    if existing is not None and existing.toko_id != toko_id:
        raise HTTPException(status.HTTP_409_CONFLICT, "ID pesanan sudah dipakai toko lain")

    if existing is not None:
        # Draft yang sama di-push ulang (kasir masih edit sebelum bayar) -
        # timpa items+metadata-nya, bukan tumpuk baris baru.
        await db.execute(delete(ItemTransaksi).where(ItemTransaksi.transaksi_id == body.id))
        existing.pelanggan_id = body.pelanggan_id
        existing.tipe_order_id = body.tipe_order_id
        existing.meja_id = body.meja_id
        existing.nomor_struk = body.nomor_struk
        existing.tanggal = body.tanggal
        existing.catatan = body.catatan
        existing.subtotal = subtotal
        existing.total = subtotal
        transaksi = existing
    else:
        transaksi = Transaksi(
            id=body.id,
            toko_id=toko_id,
            outlet_id=body.outlet_id,
            pengguna_id=pengguna_id,
            pelanggan_id=body.pelanggan_id,
            tipe_order_id=body.tipe_order_id,
            meja_id=body.meja_id,
            nomor_struk=body.nomor_struk,
            tanggal=body.tanggal,
            status="tersimpan",
            subtotal=subtotal,
            total=subtotal,
            total_bayar=Decimal("0"),
            kembalian=Decimal("0"),
            status_bayar="belum_bayar",
            catatan=body.catatan,
        )
        db.add(transaksi)
    await db.flush()

    for item in body.items:
        db.add(
            ItemTransaksi(
                transaksi_id=transaksi.id,
                produk_id=item.produk_id,
                varian_id=item.varian_id,
                nama_produk=item.nama_produk,
                qty=item.qty,
                harga_satuan=item.harga_satuan,
                subtotal=_bulatkan(item.qty * item.harga_satuan),
            )
        )

    await db.commit()
    await db.refresh(transaksi)
    return transaksi


async def hapus_pesanan_tersimpan(db: AsyncSession, *, toko_id: uuid.UUID, pesanan_id: uuid.UUID) -> None:
    """Dipanggil device SETELAH pesanan ini dibayar (jadi transaksi 'selesai'
    BARU dgn id berbeda lewat checkout biasa) - baris cadangan 'tersimpan'
    ini tidak berguna lagi. BUKAN jalur pembatalan (lihat batalkan_pesanan_
    tersimpan di bawah utk itu - beda endpoint, beda semantik: ini bukan
    kejadian bisnis yang perlu alasan/audit_log, cuma bersih2 draft yang
    sudah lunas). Idempotent HANYA utk kasus "sudah terhapus sebelumnya"
    (device boleh panggil ulang dgn aman) - id milik toko lain tetap 404
    keras (bukan diam2 no-op), supaya tidak diam2 terlihat "berhasil"
    padahal bukan resource toko ini."""
    transaksi = await db.get(Transaksi, pesanan_id)
    if transaksi is not None and transaksi.toko_id != toko_id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Pesanan tidak ditemukan")
    if transaksi is None or transaksi.status != "tersimpan":
        return
    await db.delete(transaksi)
    await db.commit()


async def batalkan_pesanan_tersimpan(
    db: AsyncSession,
    *,
    toko_id: uuid.UUID,
    pengguna_id: uuid.UUID,
    pesanan_id: uuid.UUID,
    alasan: str,
    disetujui_oleh: uuid.UUID | None,
) -> None:
    """Temuan#2 (rapikan F3.E) - pembatalan pesanan tersimpan adalah
    KEJADIAN BISNIS (kasir memutuskan batal, bukan sekadar "draft sudah
    lunas") - wajib alasan + audit_log (siapa/kapan/isi pesanan/total/
    alasan) + approval PIN owner/manajer kalau yang membatalkan TIDAK
    punya izin `transaksi.batal_pesanan` sendiri (mis. Kasir) DAN total
    pesanan di atas `batas_approval_batal_pesanan` (default Rp0 - selalu
    utk pesanan > 0, lihat app/core/config.py). Dipanggil dari DUA jalur
    yang HARUS berlaku sama persis: endpoint langsung (online) DAN
    kategori `pesanan_batal` di /sync/push (offline, lihat sync_service.py).

    Tahap 5b - `role_id` TIDAK lagi diterima sbg parameter terpisah,
    diturunkan dari `pengguna_id` (lookup Pengguna) di sini - sebelumnya
    role_id dikirim terpisah dari token, yang berarti jalur push (banyak
    karyawan berbagi SATU token device/Owner) selalu memakai role Owner
    utk cek `sudah_berizin`, bukan role karyawan yang SEBENARNYA minta
    batal (lihat identitas_service.py utk filosofi "simpan tapi tandai"
    yang sama diterapkan via validasi_dan_tandai di akhir fungsi ini)."""

    transaksi = await db.get(Transaksi, pesanan_id)
    if transaksi is not None and transaksi.toko_id != toko_id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Pesanan tidak ditemukan")
    if transaksi is None or transaksi.status != "tersimpan":
        # Idempotent - sudah dibatalkan/dihapus sebelumnya (mis. push
        # offline yang sama datang dobel), bukan error.
        return

    if not alasan or not alasan.strip():
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Alasan pembatalan wajib diisi")

    pelaku = await db.get(Pengguna, pengguna_id)
    batas = get_settings().batas_approval_batal_pesanan
    sudah_berizin = (
        pelaku is not None
        and pelaku.toko_id == toko_id
        and await has_izin(db, pelaku.role_id, "transaksi.batal_pesanan")
    )
    if not sudah_berizin and transaksi.total > batas:
        if disetujui_oleh is None:
            raise HTTPException(
                status.HTTP_403_FORBIDDEN,
                detail={
                    "kode": "batal_pesanan_butuh_approval",
                    "pesan": "Pembatalan pesanan ini butuh approval PIN owner/manajer",
                },
            )
        approver = await db.get(Pengguna, disetujui_oleh)
        if (
            approver is None
            or approver.toko_id != toko_id
            or not await has_izin(db, approver.role_id, "transaksi.batal_pesanan")
        ):
            raise HTTPException(
                status.HTTP_403_FORBIDDEN,
                detail={
                    "kode": "batal_pesanan_approval_tidak_sah",
                    "pesan": "Approval pembatalan tidak sah/bukan owner-manajer toko ini",
                },
            )

    items = (
        await db.execute(select(ItemTransaksi).where(ItemTransaksi.transaksi_id == pesanan_id))
    ).scalars().all()
    isi_pesanan = [
        {"produk_id": str(i.produk_id), "nama_produk": i.nama_produk, "qty": str(i.qty)} for i in items
    ]

    db.add(
        AuditLog(
            toko_id=toko_id,
            pengguna_id=pengguna_id,
            aksi="batalkan_pesanan_tersimpan",
            tabel="transaksi",
            record_id=transaksi.id,
            data_lama={
                "nomor_struk": transaksi.nomor_struk,
                "total": str(transaksi.total),
                "isi_pesanan": isi_pesanan,
            },
            data_baru={
                "alasan": alasan.strip(),
                "disetujui_oleh": str(disetujui_oleh) if disetujui_oleh is not None else None,
            },
        )
    )
    await validasi_dan_tandai(
        db, toko_id=toko_id, pengguna_id=pengguna_id, outlet_id=transaksi.outlet_id,
        kode_izin=None, operasi="batalkan_pesanan_tersimpan", tabel="transaksi", record_id=pesanan_id,
    )
    await db.delete(transaksi)
    await db.commit()
