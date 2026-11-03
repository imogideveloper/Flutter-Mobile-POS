"""Refund (penuh/sebagian) - aturan dokumen #7: aksi sensitif, wajib cek
izin role + audit_log (dilakukan di router, bukan di sini - sama
pembagian tanggung jawab dengan void_service). Mendukung refund SEBAGIAN:
satu transaksi bisa di-refund berkali-kali selama qty per item belum
melebihi qty aslinya dikurangi yang sudah pernah di-refund.

F3.D - nominal refund per baris dihitung PROPORSIONAL: bukan cuma
qty*harga_satuan, tapi ikut sertakan bagian diskon transaksi (member+promo)
dan service+pajak yang "melekat" ke baris itu, dibagi pakai metode largest
remainder (lihat docs/aturan_harga.md bagian Refund) supaya total semua
baris selalu PERSIS sama dengan total transaksi aslinya (tidak ada sisa
akibat pembulatan per baris)."""

import uuid
from decimal import Decimal

from fastapi import HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.audit import AuditLog, Notifikasi
from app.models.produk import Produk
from app.models.transaksi import ItemRefund, ItemTransaksi, MetodeBayar, Refund, Transaksi, TransaksiPajak, TransaksiPromo
from app.schemas.refund import RefundIn
from app.services.harga.refund_kalkulator import ItemRefundInput, RefundLineInput, hitung_refund_proporsional
from app.services.kepemilikan import get_shift_aktif
from app.services.loyalty_service import kurangi_poin_proporsional
from app.services.stok_service import catat_mutasi


async def _qty_sudah_direfund(db: AsyncSession, item_transaksi_id: uuid.UUID) -> Decimal:
    total = await db.scalar(
        select(func.coalesce(func.sum(ItemRefund.qty), 0))
        .join(Refund, Refund.id == ItemRefund.refund_id)
        .where(ItemRefund.item_transaksi_id == item_transaksi_id)
    )
    return Decimal(total or 0)


async def daftar_item_refundable(db: AsyncSession, transaksi_id: uuid.UUID) -> list[dict]:
    """F3.D.1 - dipakai layar pilih item refund di Flutter: qty ASLI
    dikurangi yang sudah pernah direfund, dihitung server (bukan Flutter)
    supaya selalu konsisten dgn validasi buat_refund di atas."""
    item_rows = (
        await db.execute(select(ItemTransaksi).where(ItemTransaksi.transaksi_id == transaksi_id))
    ).scalars().all()
    hasil = []
    for item in item_rows:
        sudah = await _qty_sudah_direfund(db, item.id)
        hasil.append({
            "item_transaksi_id": item.id,
            "nama_produk": item.nama_produk,
            "qty": item.qty,
            "harga_satuan": item.harga_satuan,
            "qty_sudah_direfund": sudah,
            "sisa_bisa_direfund": max(Decimal("0"), item.qty - sudah),
        })
    return hasil


async def _ambil_data_refund_proporsional(
    db: AsyncSession, transaksi_id: uuid.UUID
) -> tuple[tuple[ItemRefundInput, ...], Decimal, Decimal]:
    """Ambil data checkout yang SUDAH tersimpan (immutable) dan ubah jadi
    input murni utk hitung_refund_proporsional - modul itu sendiri tidak
    pernah query DB (lihat refund_kalkulator.py). diskon_transaksi_total =
    diskon_member+diskon_promo digabung (dari transaksi_promo);
    pajak_service_total = SEMUA baris transaksi_pajak digabung (service+
    pajak jadi satu pool, simplifikasi disengaja - lihat aturan_harga.md).

    Transaksi PUSH OFFLINE sejak temuan#1 (rapikan F3) BISA punya baris
    transaksi_pajak/transaksi_promo sungguhan - diisi dari rincian yang
    HP kirim (CheckoutIn.rincian_pajak_klien/rincian_promo_klien, lihat
    checkout_service.py) kalau client sudah versi baru. Client LAMA yang
    belum kirim rincian itu (atau transaksi yang dibuat SEBELUM fix ini)
    tetap tidak punya baris apa pun - total-nya jadi 0, refund utk
    transaksi semacam itu otomatis turun ke qty*harga_satuan - diskon_item
    saja (perilaku lama), dicatat sbg keterbatasan jujur di
    docs/aturan_harga.md, bukan ditutupi."""
    item_rows = (
        await db.execute(select(ItemTransaksi).where(ItemTransaksi.transaksi_id == transaksi_id))
    ).scalars().all()
    items = tuple(
        ItemRefundInput(
            item_transaksi_id=str(i.id),
            qty=Decimal(str(i.qty)),
            harga_satuan=Decimal(str(i.harga_satuan)),
            diskon=Decimal(str(i.diskon)),
            subtotal=Decimal(str(i.subtotal)),
        )
        for i in item_rows
    )

    promo_rows = (
        await db.execute(select(TransaksiPromo).where(TransaksiPromo.transaksi_id == transaksi_id))
    ).scalars().all()
    diskon_total = sum((Decimal(str(p.jumlah_diskon)) for p in promo_rows), Decimal("0"))

    pajak_rows = (
        await db.execute(select(TransaksiPajak).where(TransaksiPajak.transaksi_id == transaksi_id))
    ).scalars().all()
    pajak_service_total = sum((Decimal(str(p.jumlah)) for p in pajak_rows), Decimal("0"))

    return items, diskon_total, pajak_service_total


async def buat_refund(
    db: AsyncSession,
    *,
    toko_id: uuid.UUID,
    transaksi: Transaksi,
    pengguna_id: uuid.UUID,
    body: RefundIn,
) -> Refund:
    # Idempotency (F3.D.5) - sama pola dgn checkout_service.checkout: push
    # ulang refund yang sama (id sudah pernah diterima) tidak boleh dobel.
    if body.id is not None:
        existing = await db.get(Refund, body.id)
        if existing is not None:
            if existing.transaksi_id != transaksi.id:
                raise HTTPException(status.HTTP_409_CONFLICT, "ID refund sudah dipakai transaksi lain")
            return existing

    is_push_offline = body.id is not None

    if transaksi.status not in ("selesai", "refund_sebagian"):
        raise HTTPException(
            status.HTTP_409_CONFLICT, "Hanya transaksi 'selesai'/'refund_sebagian' yang bisa di-refund"
        )
    if not body.items:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Minimal satu item harus diisi")

    if body.metode_bayar_id is not None:
        metode = await db.get(MetodeBayar, body.metode_bayar_id)
        if metode is None or metode.toko_id != transaksi.toko_id:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Metode bayar tidak ditemukan")

    if body.shift_id is not None:
        # Wajib divalidasi milik toko+outlet transaksi ini - tanpa ini
        # toko lain bisa menebak/pasang shift_id siapa pun lewat body
        # (celah kepemilikan, lihat kepemilikan.py).
        await get_shift_aktif(db, body.shift_id, transaksi.toko_id, transaksi.outlet_id)

    # Row lock (F3.D.5) - SELECT ... FOR UPDATE thdp item_transaksi yang
    # mau direfund, supaya dua request bersamaan (mis. dua HP push refund
    # offline yang tumpang tindih) diserialize oleh DB: yang kedua baru
    # baca qty_sudah_direfund SETELAH yang pertama commit, bukan baca data
    # basi lalu sama2 lolos validasi (classic race condition). No-op aman
    # di SQLite test (tidak dukung FOR UPDATE, lihat order_service.py utk
    # precedent yang sama).
    item_ids = [e.item_transaksi_id for e in body.items]
    await db.execute(
        select(ItemTransaksi).where(ItemTransaksi.id.in_(item_ids)).with_for_update()
    )

    item_rows: dict[uuid.UUID, ItemTransaksi] = {}
    entri_dipakai = []  # (entry, qty_final) - qty_final bisa < entry.qty utk push offline yg dipotong
    for entry in body.items:
        item = await db.get(ItemTransaksi, entry.item_transaksi_id)
        if item is None or item.transaksi_id != transaksi.id:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Item transaksi tidak ditemukan")
        if entry.qty <= 0:
            raise HTTPException(status.HTTP_400_BAD_REQUEST, "Qty refund harus lebih dari 0")

        sudah_direfund = await _qty_sudah_direfund(db, item.id)
        sisa = item.qty - sudah_direfund
        if entry.qty > sisa:
            if not is_push_offline:
                raise HTTPException(
                    status.HTTP_400_BAD_REQUEST,
                    f"Qty refund ({entry.qty}) melebihi sisa yang bisa di-refund ({sisa}) utk item {item.nama_produk}",
                )
            # Push offline (F3.D.5) - barang/uang sudah keluar duluan di HP
            # sebelum tahu ada refund lain yang baru commit lebih dulu utk
            # item yang sama. "Terima yang pertama" = potong qty push ini
            # ke SISA yang masih valid (0 kalau sudah habis), bukan
            # ditolak mentah2 (device tidak bisa membatalkan kejadian yang
            # sudah terjadi) - dicatat audit_log + notifikasi owner.
            qty_dipakai = max(Decimal("0"), sisa)
            db.add(
                AuditLog(
                    toko_id=toko_id, aksi="refund_offline_melebihi_qty", tabel="item_transaksi",
                    record_id=item.id,
                    data_lama={"qty_diminta": str(entry.qty), "sisa_valid": str(sisa)},
                    data_baru={"qty_diterima": str(qty_dipakai)},
                )
            )
            db.add(
                Notifikasi(
                    toko_id=toko_id, jenis="refund_offline_melebihi_qty",
                    judul="Refund offline melebihi sisa qty",
                    isi=(
                        f"Device meminta refund {entry.qty} {item.nama_produk} tapi sisa yang "
                        f"valid cuma {sisa} (kemungkinan sudah di-refund device lain lebih dulu). "
                        f"Cuma {qty_dipakai} yang diterima - mohon ditindaklanjuti manual kalau "
                        "perlu rekonsiliasi uang/stok."
                    ),
                    ref_tipe="item_transaksi", ref_id=item.id,
                )
            )
            if qty_dipakai == 0:
                continue  # tidak ada apa pun yang bisa diterima dari baris ini
            entri_dipakai.append((entry, qty_dipakai))
        else:
            entri_dipakai.append((entry, entry.qty))
        item_rows[entry.item_transaksi_id] = item

    if not entri_dipakai:
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            "Semua item pada permintaan refund ini sudah habis direfund sebelumnya",
        )

    items_murni, diskon_total, pajak_service_total = await _ambil_data_refund_proporsional(db, transaksi.id)
    refund_lines_murni = tuple(
        RefundLineInput(item_transaksi_id=str(entry.item_transaksi_id), qty_refund=qty_final)
        for entry, qty_final in entri_dipakai
    )
    hasil_proporsional = {
        baris.item_transaksi_id: baris.jumlah
        for baris in hitung_refund_proporsional(
            items=items_murni,
            diskon_transaksi_total=diskon_total,
            pajak_service_total=pajak_service_total,
            refund_lines=refund_lines_murni,
        )
    }

    nomor_urut = (
        await db.scalar(select(func.count()).select_from(Refund).where(Refund.transaksi_id == transaksi.id))
    ) or 0
    refund = Refund(
        id=body.id if body.id is not None else uuid.uuid4(),
        transaksi_id=transaksi.id,
        # Shift TEMPAT refund ini benar2 diproses (uang keluar dari laci) -
        # tahap 3b-1 aturan #4: boleh beda dari shift transaksi asal kalau
        # refund-nya baru diproses belakangan, di shift lain.
        shift_id=body.shift_id if body.shift_id is not None else transaksi.shift_id,
        metode_bayar_id=body.metode_bayar_id,
        nomor=f"RFD-{transaksi.nomor_struk}-{nomor_urut + 1}",
        alasan=body.alasan,
        total=Decimal("0"),
        kas_dikembalikan=Decimal("0"),
        kembalikan_stok=body.kembalikan_stok,
        dibuat_oleh=pengguna_id,
        disetujui_oleh=pengguna_id,
    )
    db.add(refund)
    await db.flush()

    total_refund = Decimal("0")
    for entry, qty_final in entri_dipakai:
        item = item_rows[entry.item_transaksi_id]
        # Proporsional (F3.D.3) - diskon transaksi (member+promo) MENGURANGI
        # nominal refund, service+pajak MENAMBAH (lihat docs/aturan_harga.md
        # & refund_kalkulator.hitung_refund_proporsional utk rumus lengkap).
        jumlah = hasil_proporsional[str(entry.item_transaksi_id)]
        total_refund += jumlah

        db.add(
            ItemRefund(refund_id=refund.id, item_transaksi_id=item.id, qty=qty_final, jumlah=jumlah)
        )

        if body.kembalikan_stok:
            produk = await db.get(Produk, item.produk_id)
            if produk is not None and produk.lacak_stok:
                await catat_mutasi(
                    db,
                    toko_id=transaksi.toko_id,
                    outlet_id=transaksi.outlet_id,
                    produk_id=item.produk_id,
                    varian_id=item.varian_id,
                    jenis="refund",
                    qty=qty_final,
                    hpp_satuan=item.hpp_satuan,
                    ref_tipe="refund",
                    ref_id=refund.id,
                    dibuat_oleh=pengguna_id,
                )

    refund.total = total_refund

    # Tahap 3b-1 aturan #5: refund transaksi kasbon yang belum lunas
    # mengurangi sisa_tagihan DULU - cuma sisa lebihnya (kalau ada,
    # setelah sisa_tagihan ludes) yang benar2 dikembalikan sbg uang.
    # Refund non-kasbon (sisa_tagihan sudah 0) tidak terdampak sama
    # sekali - kas_dikembalikan == total seperti perilaku lama.
    sisa_sebelum = Decimal(str(transaksi.sisa_tagihan or 0))
    pengurangan_sisa = min(total_refund, sisa_sebelum)
    # Dua desimal (bukan _bulatkan ke rupiah bulat spt total/jumlah refund
    # di atas) - konsisten dgn kolom Money(14,2) & format sisa_tagihan yang
    # sudah dikembalikan checkout_service/pembayaran_service.
    refund.kas_dikembalikan = (total_refund - pengurangan_sisa).quantize(Decimal("0.01"))
    sisa_baru = (sisa_sebelum - pengurangan_sisa).quantize(Decimal("0.01"))
    transaksi.sisa_tagihan = sisa_baru
    if sisa_baru <= 0:
        transaksi.status_bayar = "lunas"
    elif pengurangan_sisa > 0:
        transaksi.status_bayar = "sebagian"

    # Transaksi jadi 'refund' kalau SEMUA qty semua item sudah habis
    # di-refund (termasuk refund sebelumnya), selain itu 'refund_sebagian'.
    semua_habis = True
    for item in (
        await db.execute(select(ItemTransaksi).where(ItemTransaksi.transaksi_id == transaksi.id))
    ).scalars():
        if await _qty_sudah_direfund(db, item.id) < item.qty:
            semua_habis = False
            break

    transaksi.status = "refund" if semua_habis else "refund_sebagian"

    await kurangi_poin_proporsional(
        db,
        pelanggan_id=transaksi.pelanggan_id,
        transaksi_id=transaksi.id,
        total_transaksi=transaksi.total,
        jumlah_refund=total_refund,
    )

    await db.commit()
    await db.refresh(refund)
    return refund
