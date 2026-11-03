"""Proses checkout: subtotal/diskon/service/pajak/pembulatan dihitung
lewat app/services/harga/kalkulator.py - SATU mesin hitung yang sama
dipakai keranjang Flutter (lihat docs/aturan_harga.md).

Dua jalur dgn kebijakan BERBEDA (tahap 3a bagian C/D):
- ONLINE (body.id kosong): server menghitung SEMUANYA dari database -
  harga, grosir, markup tipe_order, modifier, dan promo - body TIDAK
  PERNAH dipercaya utk itu (celah manipulasi harga). Satu-satunya diskon
  "manual" yang bisa lolos adalah yang disetujui user ber-izin
  'transaksi.diskon' (lihat _terapkan_diskon_manual). Angka yang
  tersimpan = angka server, dan itu juga yang dikembalikan ke HP.
- PUSH OFFLINE (body.id terisi): transaksi itu SUDAH terjadi di HP saat
  offline - uang yang diterima kasir sudah pasti sesuai hitungan HP saat
  itu, jadi disimpan APA ADANYA (termasuk diskon manual apa pun yang
  sudah dilakukan, disetujui sah atau tidak - sudah terjadi, tidak bisa
  dibatalkan). Server TETAP menghitung ulang dari database, tapi
  hasilnya CUMA dipakai utk audit_log (selisih harga & diskon tanpa
  approval sah) + notifikasi pemilik, TIDAK PERNAH menimpa yang
  tersimpan maupun menolak push."""

import dataclasses
import uuid
from datetime import date, timedelta
from decimal import Decimal

from fastapi import HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.deps import require_outlet_access
from app.models.akun import Pengguna
from app.models.audit import AuditLog, Notifikasi
from app.models.order import Meja, ProdukPajak, TipeOrder, TipeOrderPajak
from app.models.outlet import PengaturanOutlet
from app.models.pelanggan import LevelMember, Pelanggan
from app.models.produk import BundlingItem, HargaGrosir, HargaOutlet, Modifier, Produk, ProdukVarian, Resep
from app.models.promo import Pajak, Promo, PromoProduk
from app.models.stok import MutasiStok  # noqa: F401 - registrasi tabel
from app.models.transaksi import (
    ItemTransaksi,
    ItemTransaksiModifier,
    MetodeBayar,
    Pembayaran,
    Transaksi,
    TransaksiPajak,
    TransaksiPromo,
)
from app.schemas.transaksi import CheckoutIn, CheckoutOut, RincianPajakOut, RincianServiceOut
from app.services.fitur_service import has_fitur, kode_fitur_toko, tolak_fitur_terkunci
from app.services.harga import kalkulator as k
from app.services.identitas_service import validasi_dan_tandai
from app.services.izin_service import has_izin
from app.services.kepemilikan import get_outlet_milik_toko, get_shift_aktif, pastikan_produk_milik_toko
from app.services.loyalty_service import (
    hitung_dan_validasi_tukar_poin,
    tambah_poin_dari_transaksi,
    tukar_poin_untuk_diskon,
)
from app.services.order_service import buat_pesanan_dapur
from app.services.stok_service import catat_mutasi

_DUA_DESIMAL = Decimal("0.01")


def _m(nilai: Decimal) -> Decimal:
    """Samakan tampilan dgn kolom Money(14,2) lain di API (mis. total_bayar,
    kembalian) - kalkulator.py murni rupiah bulat (skala 0), tanpa ini
    responsnya "30000" sementara field lain "30000.00"."""

    return nilai.quantize(_DUA_DESIMAL)


@dataclasses.dataclass
class _KonteksHarga:
    items: list[k.ItemInput]  # TANPA diskon_override - lihat _terapkan_diskon_manual
    promo: k.PromoInput | None
    diskon_member_persen: Decimal | None
    tipe_order: k.TipeOrderInput | None
    pajak_default: tuple
    service_default: tuple
    pembulatan: int
    fitur_aktif: frozenset


async def _validasi_kepemilikan(
    db: AsyncSession, *, toko_id: uuid.UUID, pengguna_id: uuid.UUID, role_id: uuid.UUID, body: CheckoutIn
) -> None:
    """Semua resource yang id-nya datang dari body klien WAJIB divalidasi
    milik toko_id (dari token) di sini, SEBELUM checkout() menulis baris
    apa pun - lihat kepemilikan.py utk alasan lengkapnya. Hak akses outlet
    (Kasir hanya outlet yang jadi jatahnya - lihat app/core/deps.py)
    dicek SETELAH kepemilikan toko, supaya pesan error 404 (outlet
    memang tidak ada/bukan toko ini) didahulukan dari 403 (outlet ada,
    tapi bukan jatah pengguna ini)."""

    await get_outlet_milik_toko(db, body.outlet_id, toko_id)
    await require_outlet_access(db, pengguna_id=pengguna_id, role_id=role_id, outlet_id=body.outlet_id)

    if body.shift_id is not None:
        await get_shift_aktif(db, body.shift_id, toko_id, body.outlet_id)

    produk_ids = {item.produk_id for item in body.items}
    varian_ids = {item.varian_id for item in body.items if item.varian_id is not None}
    await pastikan_produk_milik_toko(db, produk_ids, toko_id, varian_ids=varian_ids)

    if body.pelanggan_id is not None:
        pelanggan = await db.get(Pelanggan, body.pelanggan_id)
        if pelanggan is None or pelanggan.toko_id != toko_id:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Pelanggan tidak ditemukan")

    if body.tipe_order_id is not None:
        # Fitur `tipe_order` dicek DI SINI juga (bukan cuma di CRUD
        # /tipe-order) - field ini "terselip" di body checkout, jadi toko
        # yang paketnya belum membuka fitur ini tetap bisa coba kirim
        # tipe_order_id langsung lewat body tanpa lewat endpoint CRUD-nya
        # sama sekali kalau tidak dicek di sini juga.
        if not await has_fitur(db, toko_id, "tipe_order"):
            await tolak_fitur_terkunci(db, "tipe_order")
        tipe_order = await db.get(TipeOrder, body.tipe_order_id)
        if tipe_order is None or tipe_order.toko_id != toko_id:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Tipe order tidak ditemukan")

    if body.meja_id is not None:
        # Meja tidak punya kolom toko_id sendiri - kepemilikannya lewat
        # outlet_id, yang sudah divalidasi milik toko di atas. Jadi cukup
        # cocokkan meja ini ke OUTLET YANG SAMA dgn body.outlet_id.
        meja = await db.get(Meja, body.meja_id)
        if meja is None or meja.outlet_id != body.outlet_id:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Meja tidak ditemukan")

    metode_bayar = await db.get(MetodeBayar, body.metode_bayar_id)
    if metode_bayar is None or metode_bayar.toko_id != toko_id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Metode bayar tidak ditemukan")

    if body.catatan is not None and body.catatan.strip() != "" and not await has_fitur(db, toko_id, "catatan_struk"):
        await tolak_fitur_terkunci(db, "catatan_struk")


async def _bangun_produk_pajak_map(
    db: AsyncSession, *, fitur_aktif: frozenset, produk_ids: set[uuid.UUID]
) -> dict[uuid.UUID, tuple]:
    produk_pajak_map: dict[uuid.UUID, tuple] = {}
    if "pajak_per_produk" not in fitur_aktif:
        return produk_pajak_map
    rows = (
        await db.execute(
            select(ProdukPajak.produk_id, Pajak)
            .join(Pajak, Pajak.id == ProdukPajak.pajak_id)
            .where(ProdukPajak.produk_id.in_(produk_ids), Pajak.aktif.is_(True))
        )
    ).all()
    for produk_id, pajak in rows:
        produk_pajak_map.setdefault(produk_id, ())
        produk_pajak_map[produk_id] = (
            *produk_pajak_map[produk_id],
            k.PajakInput(
                id=str(pajak.id), nama=pajak.nama, persen=pajak.persen,
                termasuk_harga=pajak.termasuk_harga, urutan=pajak.urutan,
            ),
        )
    return produk_pajak_map


async def _bangun_item_dasar(
    db: AsyncSession, *, body: CheckoutIn, produk_pajak_map: dict[uuid.UUID, tuple]
) -> list[k.ItemInput]:
    """ItemInput MURNI dari database (harga_jual/harga_outlet/harga_grosir/
    modifier) - TANPA diskon_override (diterapkan terpisah, lihat
    _terapkan_diskon_manual). Ini "kebenaran server": dipakai LANGSUNG utk
    checkout ONLINE (D.1 - body.harga_satuan/diskon per item diabaikan
    total), dan sbg basis pembanding audit utk push OFFLINE (C.2 - server
    tetap menghitung ulang, hasilnya cuma utk audit_log, tidak menimpa)."""

    produk_ids = {item.produk_id for item in body.items}
    varian_ids = {item.varian_id for item in body.items if item.varian_id is not None}

    produk_by_id = {
        p.id: p for p in (await db.execute(select(Produk).where(Produk.id.in_(produk_ids)))).scalars().all()
    }
    varian_by_id: dict[uuid.UUID, ProdukVarian] = {}
    if varian_ids:
        varian_by_id = {
            v.id: v
            for v in (await db.execute(select(ProdukVarian).where(ProdukVarian.id.in_(varian_ids)))).scalars().all()
        }

    harga_outlet_map: dict[tuple[uuid.UUID, uuid.UUID | None], Decimal] = {}
    for row in (
        await db.execute(
            select(HargaOutlet).where(HargaOutlet.outlet_id == body.outlet_id, HargaOutlet.produk_id.in_(produk_ids))
        )
    ).scalars().all():
        harga_outlet_map[(row.produk_id, row.varian_id)] = row.harga_jual

    grosir_rows = (
        await db.execute(
            select(HargaGrosir).where(
                HargaGrosir.produk_id.in_(produk_ids),
                (HargaGrosir.outlet_id.is_(None)) | (HargaGrosir.outlet_id == body.outlet_id),
            )
        )
    ).scalars().all()

    modifier_ids = {m.modifier_id for item in body.items for m in item.modifiers if m.modifier_id is not None}
    modifier_harga_map: dict[uuid.UUID, Decimal] = {}
    if modifier_ids:
        modifier_harga_map = {
            m.id: m.harga_tambahan
            for m in (await db.execute(select(Modifier).where(Modifier.id.in_(modifier_ids)))).scalars().all()
        }

    items: list[k.ItemInput] = []
    for item in body.items:
        produk = produk_by_id.get(item.produk_id)
        varian = varian_by_id.get(item.varian_id) if item.varian_id is not None else None
        harga_jual = varian.harga_jual if varian is not None else (produk.harga_jual if produk is not None else Decimal("0"))
        harga_outlet = harga_outlet_map.get((item.produk_id, item.varian_id))
        tiers = tuple(
            k.HargaGrosirTier(min_qty=row.min_qty, harga=row.harga, outlet_id=str(row.outlet_id) if row.outlet_id else None)
            for row in grosir_rows
            if row.produk_id == item.produk_id and (row.varian_id is None or row.varian_id == item.varian_id)
        )
        # modifier_id tidak dikenal (ad-hoc, tidak ada di katalog) ->
        # terpaksa percaya harga dari body (tidak ada sumber lain utk
        # divalidasi) - gap yang disengaja, didokumentasikan di laporan.
        modifiers = tuple(
            k.ModifierInput(nama=m.nama, harga=modifier_harga_map.get(m.modifier_id, m.harga))
            for m in item.modifiers
        )
        items.append(
            k.ItemInput(
                produk_id=str(item.produk_id),
                varian_id=str(item.varian_id) if item.varian_id is not None else None,
                nama_produk=item.nama_produk,
                qty=item.qty,
                harga_jual=harga_jual,
                harga_outlet=harga_outlet,
                harga_grosir_tiers=tiers,
                modifiers=modifiers,
                pajak_produk=produk_pajak_map.get(item.produk_id),
            )
        )
    return items


async def _bangun_promo(db: AsyncSession, *, toko_id: uuid.UUID, body: CheckoutIn) -> k.PromoInput | None:
    if body.promo_id is None:
        return None
    promo_row = await db.get(Promo, body.promo_id)
    if promo_row is None or promo_row.toko_id != toko_id or not promo_row.aktif:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Promo tidak ditemukan/tidak aktif")

    produk_ids: frozenset = frozenset()
    if promo_row.cakupan == "produk":
        rows = (
            await db.execute(select(PromoProduk.produk_id).where(PromoProduk.promo_id == promo_row.id))
        ).scalars().all()
        produk_ids = frozenset(str(x) for x in rows)

    return k.PromoInput(
        id=str(promo_row.id), nama=promo_row.nama, tipe=promo_row.tipe, cakupan=promo_row.cakupan,
        nilai=promo_row.nilai, min_belanja=promo_row.min_belanja, maks_diskon=promo_row.maks_diskon,
        produk_ids=produk_ids,
    )


async def _bangun_tipe_order(db: AsyncSession, *, body: CheckoutIn) -> k.TipeOrderInput | None:
    if body.tipe_order_id is None:
        return None
    tipe_order_row = await db.get(TipeOrder, body.tipe_order_id)
    pajak_ids = (
        await db.execute(select(TipeOrderPajak.pajak_id).where(TipeOrderPajak.tipe_order_id == body.tipe_order_id))
    ).scalars().all()
    markup = tipe_order_row.markup_persen if tipe_order_row is not None else Decimal("0")
    return k.TipeOrderInput(id=str(body.tipe_order_id), markup_persen=markup, pajak_ids=frozenset(str(p) for p in pajak_ids))


async def _bangun_konteks_harga(db: AsyncSession, *, toko_id: uuid.UUID, body: CheckoutIn) -> _KonteksHarga:
    fitur_aktif = frozenset(await kode_fitur_toko(db, toko_id))
    produk_ids = {item.produk_id for item in body.items}

    produk_pajak_map = await _bangun_produk_pajak_map(db, fitur_aktif=fitur_aktif, produk_ids=produk_ids)
    items = await _bangun_item_dasar(db, body=body, produk_pajak_map=produk_pajak_map)
    promo = await _bangun_promo(db, toko_id=toko_id, body=body)
    tipe_order = await _bangun_tipe_order(db, body=body)

    diskon_member_persen: Decimal | None = None
    if body.pelanggan_id is not None:
        pelanggan = await db.get(Pelanggan, body.pelanggan_id)
        if pelanggan is not None and pelanggan.level_member_id is not None:
            level = await db.get(LevelMember, pelanggan.level_member_id)
            if level is not None:
                diskon_member_persen = level.diskon_persen

    pajak_rows = (
        await db.execute(select(Pajak).where(Pajak.toko_id == toko_id, Pajak.aktif.is_(True)))
    ).scalars().all()
    pajak_default = tuple(
        k.PajakInput(id=str(p.id), nama=p.nama, persen=p.persen, termasuk_harga=p.termasuk_harga, urutan=p.urutan)
        for p in pajak_rows if p.tipe == "pajak"
    )
    service_default = tuple(
        k.PajakInput(id=str(p.id), nama=p.nama, persen=p.persen, termasuk_harga=p.termasuk_harga, urutan=p.urutan)
        for p in pajak_rows if p.tipe == "service"
    )

    pengaturan = await db.get(PengaturanOutlet, body.outlet_id)
    pembulatan = pengaturan.pembulatan if pengaturan is not None else 0

    return _KonteksHarga(
        items=items, promo=promo, diskon_member_persen=diskon_member_persen, tipe_order=tipe_order,
        pajak_default=pajak_default, service_default=service_default, pembulatan=pembulatan, fitur_aktif=fitur_aktif,
    )


async def _cek_izin_diskon_manual(db: AsyncSession, *, toko_id: uuid.UUID, approver_id: uuid.UUID | None) -> bool:
    if approver_id is None:
        return False
    approver = await db.get(Pengguna, approver_id)
    if approver is None or approver.toko_id != toko_id:
        return False
    return await has_izin(db, approver.role_id, "transaksi.diskon")


async def _terapkan_diskon_manual(
    db: AsyncSession, *, toko_id: uuid.UUID, body: CheckoutIn, konteks: _KonteksHarga, tolak_jika_invalid: bool
) -> tuple[list[k.ItemInput], list[dict], bool]:
    """Terapkan diskon manual (ItemTransaksiIn.diskon > 0) ke item yg
    disetujui+valid SAJA. Return (items_final, log_entries_utk_audit,
    ada_yang_tidak_sah).

    tolak_jika_invalid=True (checkout ONLINE, D.2): raise 403 kalau ADA
    item minta diskon manual tapi approver tidak valid/tidak berizin,
    atau nilainya negatif/melebihi garis kotor baris.
    tolak_jika_invalid=False (push OFFLINE, D.3): tidak pernah menolak -
    diskon yg tidak sah/tidak valid tetap DISIMPAN (sudah terjadi), cuma
    dilaporkan lewat `ada_yang_tidak_sah` supaya pemanggil mencatat
    audit_log+notifikasi. Diskon yg SAH tetap diterapkan ke item (dipakai
    jadi basis pembanding audit yang lebih presisi - selisih yang
    dilaporkan tidak ikut "disalahkan" krn diskon yang memang legit)."""

    item_manual = [i for i, item in enumerate(body.items) if item.diskon and item.diskon != 0]
    if not item_manual:
        return konteks.items, [], False

    izin_ok = await _cek_izin_diskon_manual(db, toko_id=toko_id, approver_id=body.diskon_manual_disetujui_oleh)
    if not izin_ok:
        if tolak_jika_invalid:
            raise HTTPException(
                status.HTTP_403_FORBIDDEN,
                detail={"kode": "diskon_manual_tidak_diizinkan", "pesan": "Diskon manual butuh approval izin transaksi.diskon"},
            )
        return konteks.items, [], True

    items_final = list(konteks.items)
    log_entries: list[dict] = []
    ada_tidak_valid = False
    for i in item_manual:
        garis_kotor = k.bulatkan(konteks.items[i].qty * k.harga_satuan_item(konteks.items[i], konteks.fitur_aktif, konteks.tipe_order))
        nilai = body.items[i].diskon
        if nilai < 0 or nilai > garis_kotor:
            if tolak_jika_invalid:
                raise HTTPException(
                    status.HTTP_403_FORBIDDEN,
                    detail={"kode": "diskon_manual_tidak_valid", "pesan": "Diskon manual negatif atau melebihi subtotal baris"},
                )
            ada_tidak_valid = True
            continue
        items_final[i] = dataclasses.replace(konteks.items[i], diskon_override=nilai)
        log_entries.append({
            "produk_id": str(body.items[i].produk_id),
            "diskon": str(nilai),
            "disetujui_oleh": str(body.diskon_manual_disetujui_oleh),
        })
    return items_final, log_entries, ada_tidak_valid


def _bulat_atau(nilai: Decimal | None, fallback: Decimal) -> Decimal:
    return _m(nilai) if nilai is not None else _m(fallback)


async def _catat_selisih_harga(
    db: AsyncSession, *, toko_id: uuid.UUID, transaksi_id: uuid.UUID, klien: dict, server: dict
) -> None:
    """Transaksi offline yang di-push (body.id terisi) sudah LUNAS
    dibayar di HP berdasarkan hitungan HP sendiri saat itu - kalau hasil
    hitung ulang server (dari database, SEKARANG) beda, transaksi TETAP
    disimpan apa adanya (jangan pernah menolak transaksi yang
    pelanggannya sudah bayar). Rinciannya (bukan cuma total) dicatat di
    sini utk diinvestigasi, BUKAN auto-dikoreksi diam-diam."""

    db.add(
        AuditLog(
            toko_id=toko_id, aksi="checkout_selisih_harga", tabel="transaksi", record_id=transaksi_id,
            data_lama=klien, data_baru=server,
        )
    )
    db.add(
        Notifikasi(
            toko_id=toko_id, jenis="selisih_harga", judul="Selisih hitung harga transaksi offline",
            isi=(
                f"Total dari HP {klien.get('total')}, hitung ulang server {server.get('total')}. "
                "Transaksi tetap disimpan apa adanya - mohon diperiksa."
            ),
            ref_tipe="transaksi", ref_id=transaksi_id,
        )
    )


async def _catat_diskon_tanpa_approval(db: AsyncSession, *, toko_id: uuid.UUID, transaksi_id: uuid.UUID) -> None:
    db.add(
        AuditLog(
            toko_id=toko_id, aksi="diskon_manual_tanpa_approval_sah", tabel="transaksi", record_id=transaksi_id,
            data_baru={"catatan": "Push offline berisi diskon manual tanpa approval izin transaksi.diskon yang sah"},
        )
    )
    db.add(
        Notifikasi(
            toko_id=toko_id, jenis="diskon_tanpa_approval", judul="Diskon manual tanpa approval sah",
            isi="Transaksi offline ini berisi diskon manual tanpa approval izin transaksi.diskon yang sah. Mohon diperiksa.",
            ref_tipe="transaksi", ref_id=transaksi_id,
        )
    )


async def _potong_stok_item(
    db: AsyncSession,
    *,
    toko_id: uuid.UUID,
    outlet_id: uuid.UUID,
    transaksi_id: uuid.UUID,
    pengguna_id: uuid.UUID,
    produk: Produk,
    varian_id: uuid.UUID | None,
    qty_terjual: Decimal,
    hpp_satuan: Decimal,
) -> None:
    """Potong stok utk SATU produk terjual, cascading sesuai jenisnya:
    bundling -> komponen (bundling_item, qty proporsional) -> (kalau
    komponennya sendiri pakai_resep) bahan baku resep komponen itu;
    pakai_resep -> bahan baku resep produk itu; biasa -> stok produk itu
    sendiri. Bundle berisi bundle lain sudah ditolak saat disimpan
    (routers/produk_lanjutan.py), jadi cukup satu level expand di sini."""

    if produk.tipe == "bundling":
        komponen_rows = (
            await db.execute(
                select(BundlingItem, Produk)
                .join(Produk, Produk.id == BundlingItem.produk_id)
                .where(BundlingItem.bundling_produk_id == produk.id, BundlingItem.deleted_at.is_(None))
            )
        ).all()
        for komponen, komponen_produk in komponen_rows:
            qty_komponen = komponen.qty * qty_terjual
            if komponen_produk.pakai_resep:
                await _potong_resep(
                    db, toko_id=toko_id, outlet_id=outlet_id, transaksi_id=transaksi_id,
                    pengguna_id=pengguna_id, produk_id=komponen_produk.id, varian_id=komponen.varian_id,
                    qty_terjual=qty_komponen,
                )
            else:
                await catat_mutasi(
                    db, toko_id=toko_id, outlet_id=outlet_id, produk_id=komponen_produk.id,
                    varian_id=komponen.varian_id, jenis="penjualan", qty=-qty_komponen,
                    ref_tipe="transaksi", ref_id=transaksi_id, dibuat_oleh=pengguna_id,
                )
    elif produk.pakai_resep:
        await _potong_resep(
            db, toko_id=toko_id, outlet_id=outlet_id, transaksi_id=transaksi_id, pengguna_id=pengguna_id,
            produk_id=produk.id, varian_id=varian_id, qty_terjual=qty_terjual,
        )
    else:
        await catat_mutasi(
            db, toko_id=toko_id, outlet_id=outlet_id, produk_id=produk.id, varian_id=varian_id,
            jenis="penjualan", qty=-qty_terjual, hpp_satuan=hpp_satuan,
            ref_tipe="transaksi", ref_id=transaksi_id, dibuat_oleh=pengguna_id,
        )


async def _potong_resep(
    db: AsyncSession, *, toko_id, outlet_id, transaksi_id, pengguna_id, produk_id, varian_id, qty_terjual
) -> None:
    resep_rows = (
        await db.execute(select(Resep).where(Resep.produk_id == produk_id, Resep.deleted_at.is_(None)))
    ).scalars().all()
    for resep in resep_rows:
        if resep.varian_id is not None and resep.varian_id != varian_id:
            continue
        await catat_mutasi(
            db, toko_id=toko_id, outlet_id=outlet_id, produk_id=resep.bahan_id, varian_id=None,
            jenis="penjualan", qty=-(resep.qty * qty_terjual),
            ref_tipe="transaksi", ref_id=transaksi_id, dibuat_oleh=pengguna_id,
        )


async def _total_utang_pelanggan(db: AsyncSession, pelanggan_id: uuid.UUID) -> Decimal:
    total = await db.scalar(
        select(func.coalesce(func.sum(Transaksi.sisa_tagihan), 0)).where(
            Transaksi.pelanggan_id == pelanggan_id,
            Transaksi.status == "selesai",
            Transaksi.status_bayar != "lunas",
            Transaksi.deleted_at.is_(None),
        )
    )
    return Decimal(str(total or 0))


async def _siapkan_pembayaran_awal(
    db: AsyncSession, *, toko_id: uuid.UUID, body: CheckoutIn, total: Decimal,
    is_push_offline: bool, transaksi_id: uuid.UUID,
) -> tuple[Decimal, str, Decimal, date | None]:
    """Tentukan (kembalian, status_bayar, sisa_tagihan, jatuh_tempo) dari
    total_bayar vs total (tahap 3b-1). Kasbon (total_bayar < total) WAJIB
    fitur 'kasbon' + pelanggan_id (aturan #1); DP (0 < total_bayar < total)
    WAJIB fitur 'dp_kasbon' TAMBAHAN - tanpa itu kasbon cuma boleh bayar 0
    di awal (aturan #2). batas_kasbon pelanggan (kalau diisi) dicek di
    sini juga (aturan #5).

    Gating fitur ('kasbon'/'dp_kasbon'/wajib pelanggan) berlaku utk ONLINE
    **dan** PUSH - beda dari perbedaan ANGKA harga yang ditoleransi push
    (lihat docstring modul): "boleh pakai fitur ini sama sekali atau tidak"
    bukan bagian dari toleransi itu, sama seperti tipe_order/catatan_struk
    di _validasi_kepemilikan.

    batas_kasbon BEDA perlakuannya (tahap 4 bagian A.2): uang kasbon push
    offline SUDAH terjadi di HP (barang sudah dibawa pelanggan) - menolak
    push itu tidak membatalkan kejadian itu, cuma membuat transaksi hilang
    dari server. Jadi push yang melampaui batas_kasbon TETAP diterima,
    dicatat ke audit_log + notifikasi owner utk ditindaklanjuti manual.
    ONLINE tetap ditolak 403 sebelum apa pun terjadi (sama seperti dulu)."""

    if body.total_bayar >= total:
        return body.total_bayar - total, "lunas", Decimal("0"), None

    if not await has_fitur(db, toko_id, "kasbon"):
        await tolak_fitur_terkunci(db, "kasbon")
    if body.pelanggan_id is None:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            detail={"kode": "kasbon_butuh_pelanggan", "pesan": "Kasbon wajib memilih pelanggan"},
        )
    if body.total_bayar > 0 and not await has_fitur(db, toko_id, "dp_kasbon"):
        await tolak_fitur_terkunci(db, "dp_kasbon")

    sisa_tagihan = total - body.total_bayar
    pelanggan = await db.get(Pelanggan, body.pelanggan_id)
    if pelanggan is not None and pelanggan.batas_kasbon is not None:
        utang_sekarang = await _total_utang_pelanggan(db, pelanggan.id)
        if utang_sekarang + sisa_tagihan > pelanggan.batas_kasbon:
            if not is_push_offline:
                raise HTTPException(
                    status.HTTP_403_FORBIDDEN,
                    detail={
                        "kode": "batas_kasbon_terlampaui",
                        "batas": str(pelanggan.batas_kasbon),
                        "utang_sekarang": str(utang_sekarang),
                        "pesan": "Kasbon ini membuat total utang pelanggan melebihi batas_kasbon",
                    },
                )
            db.add(
                AuditLog(
                    toko_id=toko_id, aksi="kasbon_lewati_batas", tabel="transaksi", record_id=transaksi_id,
                    data_lama={"batas_kasbon": str(pelanggan.batas_kasbon), "utang_sebelum": str(utang_sekarang)},
                    data_baru={"sisa_tagihan_baru": str(sisa_tagihan)},
                )
            )
            db.add(
                Notifikasi(
                    toko_id=toko_id, jenis="kasbon_lewati_batas",
                    judul="Kasbon offline melampaui batas pelanggan",
                    isi=(
                        f"Transaksi offline ini membuat total utang pelanggan jadi "
                        f"{utang_sekarang + sisa_tagihan} - melebihi batas_kasbon "
                        f"{pelanggan.batas_kasbon}. Uang/barang sudah keluar di HP, transaksi "
                        "tetap disimpan - mohon ditindaklanjuti manual."
                    ),
                    ref_tipe="transaksi", ref_id=transaksi_id,
                )
            )

    status_bayar = "belum_bayar" if body.total_bayar == 0 else "sebagian"
    hari = body.jatuh_tempo_hari if body.jatuh_tempo_hari is not None else 7
    jatuh_tempo = (body.tanggal + timedelta(days=hari)).date()
    return Decimal("0"), status_bayar, sisa_tagihan, jatuh_tempo


async def checkout(
    db: AsyncSession, *, toko_id: uuid.UUID, pengguna_id: uuid.UUID, role_id: uuid.UUID, body: CheckoutIn
) -> CheckoutOut:
    if body.id is not None:
        existing = await db.get(Transaksi, body.id)
        if existing is not None:
            if existing.toko_id != toko_id:
                raise HTTPException(status.HTTP_409_CONFLICT, "ID transaksi sudah dipakai toko lain")
            return await _ke_checkout_out(db, existing)

    await _validasi_kepemilikan(db, toko_id=toko_id, pengguna_id=pengguna_id, role_id=role_id, body=body)

    is_push_offline = body.id is not None
    # Tahap 5b - utk push, identitas yang SEBENARNYA dicatat adalah
    # karyawan yang login di HP saat itu (body.pengguna_id), BUKAN token
    # device/Owner yang kebetulan dipakai mengirim push - lihat
    # CheckoutIn.pengguna_id. Online tetap pakai identitas token apa pun
    # isi body (token online SUDAH identitas sungguhan sejak PIN login
    # online, desain #6).
    pengguna_id_efektif = (
        body.pengguna_id if (is_push_offline and body.pengguna_id is not None) else pengguna_id
    )
    konteks = await _bangun_konteks_harga(db, toko_id=toko_id, body=body)

    items_final, diskon_log_entries, ada_diskon_tidak_sah = await _terapkan_diskon_manual(
        db, toko_id=toko_id, body=body, konteks=konteks, tolak_jika_invalid=not is_push_offline,
    )

    hasil_server = k.hitung(
        k.TransaksiInput(
            items=tuple(items_final), fitur_aktif=konteks.fitur_aktif, promo=konteks.promo,
            diskon_member_persen=konteks.diskon_member_persen, tipe_order=konteks.tipe_order,
            pajak_default=konteks.pajak_default, service_default=konteks.service_default,
            pembulatan=konteks.pembulatan,
        )
    )

    if is_push_offline:
        # C.2 - simpan APA ADANYA dari HP, server TIDAK PERNAH menimpa.
        subtotal_simpan = _bulat_atau(body.subtotal_klien, sum((i.qty * i.harga_satuan - i.diskon for i in body.items), Decimal("0")))
        diskon_simpan = _bulat_atau(body.total_diskon_klien, Decimal("0"))
        pajak_simpan = _bulat_atau(body.total_pajak_klien, Decimal("0"))
        pembulatan_simpan = _bulat_atau(body.pembulatan_klien, Decimal("0"))
        total_simpan = _bulat_atau(
            body.total_klien, subtotal_simpan - diskon_simpan + pajak_simpan + pembulatan_simpan
        )
        item_harga_satuan = {i: item.harga_satuan for i, item in enumerate(body.items)}
        item_diskon = {i: item.diskon for i, item in enumerate(body.items)}
        modifier_harga_terpakai = None  # None = pakai apa adanya dari body (push)
    else:
        # D.1/C.1 - server SELALU memakai & mengembalikan hasil hitungnya
        # sendiri, body tidak pernah dipercaya utk harga.
        subtotal_simpan = _m(hasil_server.subtotal)
        diskon_simpan = _m(hasil_server.total_diskon)
        pajak_simpan = _m(hasil_server.pajak + hasil_server.service)
        pembulatan_simpan = _m(hasil_server.pembulatan)
        total_simpan = _m(hasil_server.total)
        item_harga_satuan = {i: r.harga_satuan for i, r in enumerate(hasil_server.items)}
        item_diskon = {i: r.diskon for i, r in enumerate(hasil_server.items)}
        # Modifier yang benar2 dipakai server = yang sudah di-resolve di
        # _bangun_item_dasar (items_final[i].modifiers, urutan sama dgn body).
        modifier_harga_terpakai = {
            i: {j: mod.harga for j, mod in enumerate(items_final[i].modifiers)} for i in range(len(items_final))
        }

    # Tukar poin (modul 10) - SETELAH subtotal/diskon/pajak diketahui tapi
    # SEBELUM kasbon/DP (diskon ini wajib ikut mengecilkan `total` yang
    # dipakai utk menentukan lunas/kasbon/kembalian di bawah). ONLINE:
    # server hitung+validasi dari DB sendiri lalu MEMOTONG total_simpan.
    # PUSH OFFLINE: dipercaya apa adanya dari body.diskon_poin_klien
    # (sudah dipotong HP ke body.total_klien duluan) - TIDAK dipotong lagi
    # di sini drpd dobel potong.
    if is_push_offline:
        diskon_poin = _bulat_atau(body.diskon_poin_klien, Decimal("0"))
    else:
        if body.poin_ditukar > 0 and not await has_fitur(db, toko_id, "poin_loyalitas"):
            await tolak_fitur_terkunci(db, "poin_loyalitas")
        diskon_poin = await hitung_dan_validasi_tukar_poin(
            db, toko_id=toko_id, pelanggan_id=body.pelanggan_id,
            poin_ditukar=body.poin_ditukar, total_tersedia=total_simpan,
        )
        if diskon_poin > 0:
            diskon_simpan = _m(diskon_simpan + diskon_poin)
            total_simpan = _m(total_simpan - diskon_poin)

    # Kasbon/DP (tahap 3b-1) - SETELAH total_simpan diketahui, berlaku utk
    # online maupun push (lihat docstring _siapkan_pembayaran_awal).
    transaksi_id = body.id or uuid.uuid4()
    kembalian, status_bayar, sisa_tagihan, jatuh_tempo = await _siapkan_pembayaran_awal(
        db, toko_id=toko_id, body=body, total=total_simpan,
        is_push_offline=is_push_offline, transaksi_id=transaksi_id,
    )

    transaksi = Transaksi(
        id=transaksi_id,
        toko_id=toko_id,
        outlet_id=body.outlet_id,
        shift_id=body.shift_id,
        pengguna_id=pengguna_id_efektif,
        pelanggan_id=body.pelanggan_id,
        tipe_order_id=body.tipe_order_id,
        meja_id=body.meja_id,
        nomor_struk=body.nomor_struk,
        tanggal=body.tanggal,
        status="selesai",
        subtotal=subtotal_simpan,
        total_diskon=diskon_simpan,
        total_pajak=pajak_simpan,
        pembulatan=pembulatan_simpan,
        total=total_simpan,
        total_bayar=body.total_bayar,
        kembalian=_m(kembalian),
        catatan=body.catatan,
        status_bayar=status_bayar,
        sisa_tagihan=_m(sisa_tagihan),
        jatuh_tempo=jatuh_tempo,
        snapshot_struk=body.snapshot_struk,
    )
    db.add(transaksi)
    await db.flush()

    if is_push_offline:
        if body.total_klien is not None and _m(body.total_klien) != _m(hasil_server.total):
            await _catat_selisih_harga(
                db, toko_id=toko_id, transaksi_id=transaksi.id,
                klien={
                    "subtotal": str(subtotal_simpan), "diskon": str(diskon_simpan),
                    "pajak": str(pajak_simpan), "pembulatan": str(pembulatan_simpan), "total": str(total_simpan),
                },
                server={
                    "subtotal": str(_m(hasil_server.subtotal)), "diskon": str(_m(hasil_server.total_diskon)),
                    "pajak": str(_m(hasil_server.pajak + hasil_server.service)),
                    "pembulatan": str(_m(hasil_server.pembulatan)), "total": str(_m(hasil_server.total)),
                },
            )
        if ada_diskon_tidak_sah:
            await _catat_diskon_tanpa_approval(db, toko_id=toko_id, transaksi_id=transaksi.id)
        await validasi_dan_tandai(
            db, toko_id=toko_id, pengguna_id=pengguna_id_efektif, outlet_id=body.outlet_id,
            kode_izin="transaksi.buat", operasi="checkout", tabel="transaksi", record_id=transaksi.id,
        )
    else:
        for entry in diskon_log_entries:
            db.add(
                AuditLog(
                    toko_id=toko_id, aksi="diskon_manual_disetujui", tabel="transaksi", record_id=transaksi.id,
                    data_baru=entry,
                )
            )

    produk_ids = {item.produk_id for item in body.items}
    produk_by_id = {
        p.id: p for p in (await db.execute(select(Produk).where(Produk.id.in_(produk_ids)))).scalars().all()
    }

    for idx, item in enumerate(body.items):
        item_id = uuid.uuid4()
        harga_satuan_simpan = item_harga_satuan[idx]
        diskon_item_simpan = item_diskon[idx]
        db.add(
            ItemTransaksi(
                id=item_id,
                transaksi_id=transaksi.id,
                produk_id=item.produk_id,
                varian_id=item.varian_id,
                nama_produk=item.nama_produk,
                qty=item.qty,
                harga_satuan=harga_satuan_simpan,
                hpp_satuan=item.hpp_satuan,
                diskon=diskon_item_simpan,
                subtotal=(item.qty * harga_satuan_simpan) - diskon_item_simpan,
            )
        )
        for j, modifier in enumerate(item.modifiers):
            harga_modifier = (
                modifier.harga if modifier_harga_terpakai is None else modifier_harga_terpakai[idx][j]
            )
            db.add(
                ItemTransaksiModifier(
                    item_transaksi_id=item_id,
                    modifier_id=modifier.modifier_id,
                    nama=modifier.nama,
                    harga=harga_modifier,
                )
            )

        if not item.lacak_stok:
            continue

        produk = produk_by_id.get(item.produk_id)
        if produk is not None:
            await _potong_stok_item(
                db, toko_id=toko_id, outlet_id=body.outlet_id, transaksi_id=transaksi.id,
                pengguna_id=pengguna_id, produk=produk, varian_id=item.varian_id,
                qty_terjual=item.qty, hpp_satuan=item.hpp_satuan,
            )

    if body.total_bayar > 0 and body.split_pembayaran:
        # Split payment (F3.A) - validasi jumlah semua baris PERSIS sama
        # dgn total_bayar (bukan >= / <=, supaya tidak ada uang "hilang"
        # atau dobel dicatat), tiap metode_bayar WAJIB milik toko ini.
        jumlah_split = sum((baris.jumlah for baris in body.split_pembayaran), Decimal("0"))
        if jumlah_split != body.total_bayar:
            raise HTTPException(
                status.HTTP_400_BAD_REQUEST,
                detail={
                    "kode": "split_pembayaran_tidak_sama",
                    "pesan": f"Total split_pembayaran ({jumlah_split}) harus persis sama dgn total_bayar ({body.total_bayar})",
                },
            )
        for baris in body.split_pembayaran:
            metode = await db.get(MetodeBayar, baris.metode_bayar_id)
            if metode is None or metode.toko_id != toko_id:
                raise HTTPException(status.HTTP_404_NOT_FOUND, "Metode bayar (split) tidak ditemukan")
            if baris.jumlah <= 0:
                raise HTTPException(status.HTTP_400_BAD_REQUEST, "Jumlah split_pembayaran harus > 0")
            # payload_gateway EKSPLISIT (temuan A.1 - mis. penanda QRIS
            # manual) MENANG kalau diisi; else fallback ke payload
            # empat_digit_akhir_kartu lama (keduanya tidak pernah
            # digabung - satu baris cuma satu jenis penanda).
            payload = baris.payload_gateway or (
                {"empat_digit_akhir_kartu": baris.empat_digit_akhir_kartu}
                if baris.empat_digit_akhir_kartu
                else None
            )
            db.add(
                Pembayaran(
                    transaksi_id=transaksi.id,
                    shift_id=body.shift_id,
                    metode_bayar_id=baris.metode_bayar_id,
                    jumlah=baris.jumlah,
                    jenis="penuh" if status_bayar == "lunas" else "dp",
                    status="berhasil",
                    ref_gateway=baris.nomor_referensi,
                    payload_gateway=payload,
                    dibayar_pada=body.tanggal,
                )
            )
    elif body.total_bayar > 0:
        # jumlah>0 WAJIB (CHECK constraint pembayaran.jumlah) - kasbon
        # yang bayar 0 di awal (aturan #2) TIDAK membuat baris pembayaran
        # sama sekali, baru ada saat cicilan/pelunasan pertama (lihat
        # pembayaran_service.py).
        db.add(
            Pembayaran(
                transaksi_id=transaksi.id,
                shift_id=body.shift_id,
                metode_bayar_id=body.metode_bayar_id,
                jumlah=body.total_bayar,
                jenis="penuh" if status_bayar == "lunas" else "dp",
                status="berhasil",
                payload_gateway=body.payload_gateway,
                dibayar_pada=body.tanggal,
            )
        )

    diskon_member_out = Decimal("0")
    diskon_promo_out = Decimal("0")
    service_out = Decimal("0")
    rincian_pajak_out: list[RincianPajakOut] = []
    rincian_service_out: list[RincianServiceOut] = []

    if not is_push_offline:
        # Rincian per-baris (transaksi_pajak/transaksi_promo) HANYA
        # ditulis utk checkout ONLINE - server punya rincian lengkap dari
        # hasil_server. Push offline tidak mengirim rincian per-pajak,
        # cuma aggregate (lihat docstring field *_klien) - struk aslinya
        # sudah tercetak di HP saat sale terjadi, baris ini hanya utk
        # pembukuan agregat.
        for rincian in hasil_server.rincian_pajak:
            db.add(TransaksiPajak(transaksi_id=transaksi.id, nama=rincian.nama, persen=rincian.persen, jumlah=_m(rincian.jumlah)))
            rincian_pajak_out.append(RincianPajakOut(nama=rincian.nama, persen=rincian.persen, jumlah=_m(rincian.jumlah)))
        for rincian in hasil_server.rincian_service:
            db.add(TransaksiPajak(transaksi_id=transaksi.id, nama=rincian.nama, persen=rincian.persen, jumlah=_m(rincian.jumlah)))
            rincian_service_out.append(RincianServiceOut(nama=rincian.nama, persen=rincian.persen, jumlah=_m(rincian.jumlah)))
        service_out = _m(hasil_server.service)

        if konteks.promo is not None and hasil_server.diskon_promo > 0:
            promo_row = await db.get(Promo, body.promo_id)
            if promo_row is not None:
                db.add(
                    TransaksiPromo(
                        transaksi_id=transaksi.id, promo_id=promo_row.id, nama=promo_row.nama,
                        jumlah_diskon=_m(hasil_server.diskon_promo),
                    )
                )
                diskon_promo_out = _m(hasil_server.diskon_promo)
        if hasil_server.diskon_member > 0:
            db.add(
                TransaksiPromo(
                    transaksi_id=transaksi.id, promo_id=None, nama="Diskon member", jumlah_diskon=_m(hasil_server.diskon_member)
                )
            )
            diskon_member_out = _m(hasil_server.diskon_member)
    else:
        # Temuan#1 (rapikan F3) - HP SEKARANG bisa kirim rincian pajak/
        # service + promo/member yang sudah dihitung lokal (lib/core/harga/
        # kalkulator.dart). Kalau dikirim, simpan APA ADANYA ke
        # transaksi_pajak/transaksi_promo (C.2) - supaya refund proporsional
        # (refund_service.py) & laporan per-jenis bisa jalan SAMA PERSIS
        # dgn transaksi online, bukan cuma turun ke satu baris gabungan.
        # id yang tidak dikenal/bukan milik toko ini disimpan NULL +
        # audit_log (bukan ditolak - uang sudah diterima di HP). Client
        # lama yang belum kirim rincian (atau mengirim kosong) tetap
        # didukung - fallback ke respons satu baris gabungan seperti
        # sebelumnya (tanpa baris transaksi_pajak/transaksi_promo -> refund
        # transaksi semacam ini turun ke formula sederhana lama, lihat
        # docs/aturan_harga.md).
        if body.rincian_pajak_klien:
            for r in body.rincian_pajak_klien:
                pajak_id_valid = None
                if r.pajak_id is not None:
                    pajak_row = await db.get(Pajak, r.pajak_id)
                    if pajak_row is not None and pajak_row.toko_id == toko_id:
                        pajak_id_valid = pajak_row.id
                    else:
                        db.add(
                            AuditLog(
                                toko_id=toko_id, aksi="offline_pajak_id_tak_dikenal",
                                tabel="transaksi_pajak", record_id=transaksi.id,
                                data_lama={"pajak_id": str(r.pajak_id)},
                                data_baru={"nama": r.nama, "jumlah": str(r.jumlah)},
                            )
                        )
                db.add(
                    TransaksiPajak(
                        transaksi_id=transaksi.id, pajak_id=pajak_id_valid, nama=r.nama,
                        persen=r.persen, jumlah=_m(r.jumlah),
                    )
                )
        if body.rincian_promo_klien:
            for r in body.rincian_promo_klien:
                promo_id_valid = None
                if r.promo_id is not None:
                    promo_row = await db.get(Promo, r.promo_id)
                    if promo_row is not None and promo_row.toko_id == toko_id:
                        promo_id_valid = promo_row.id
                    else:
                        db.add(
                            AuditLog(
                                toko_id=toko_id, aksi="offline_promo_id_tak_dikenal",
                                tabel="transaksi_promo", record_id=transaksi.id,
                                data_lama={"promo_id": str(r.promo_id)},
                                data_baru={"nama": r.nama, "jumlah": str(r.jumlah_diskon)},
                            )
                        )
                db.add(
                    TransaksiPromo(
                        transaksi_id=transaksi.id, promo_id=promo_id_valid, nama=r.nama,
                        jumlah_diskon=_m(r.jumlah_diskon),
                    )
                )
        diskon_member_out = Decimal("0.00")
        diskon_promo_out = diskon_simpan
        service_out = Decimal("0.00")

    diskon_poin_out = Decimal("0.00")
    if body.poin_ditukar > 0 and body.pelanggan_id is not None:
        # Dicatat utk ONLINE **dan** PUSH - poin pelanggan wajib benar2
        # berkurang di server kapan pun redemption-nya terjadi (app ini
        # offline-first, SEMUA transaksi nyata lewat jalur push, bukan
        # cuma lewat jalur online).
        await tukar_poin_untuk_diskon(
            db, pelanggan_id=body.pelanggan_id, transaksi_id=transaksi.id, poin_ditukar=body.poin_ditukar,
        )
        if diskon_poin > 0:
            db.add(
                TransaksiPromo(
                    transaksi_id=transaksi.id, promo_id=None, nama="Tukar poin", jumlah_diskon=diskon_poin,
                )
            )
            diskon_poin_out = diskon_poin

    # poin_loyalitas (tahap 3a A.1) - toko tanpa fitur ini tetap checkout
    # normal, cuma TIDAK dapat poin (bukan error). `total_simpan` di sini
    # SUDAH dipotong diskon_poin (lihat di atas) - sengaja TIDAK dapat
    # poin baru dari porsi yang dibayar pakai poin itu sendiri sendiri.
    if await has_fitur(db, toko_id, "poin_loyalitas"):
        await tambah_poin_dari_transaksi(
            db, toko_id=toko_id, pelanggan_id=body.pelanggan_id, transaksi_id=transaksi.id, total=total_simpan
        )

    await db.commit()
    await db.refresh(transaksi)

    # Tiket dapur hanya dibuat kalau toko punya fitur `tiket_dapur` (paket
    # Bisnis, aturan dokumen #4.2) - toko retail tanpa dapur tidak perlu
    # baris pesanan_dapur sama sekali.
    if await has_fitur(db, toko_id, "tiket_dapur"):
        await buat_pesanan_dapur(db, transaksi)

    return CheckoutOut(
        id=transaksi.id,
        nomor_struk=transaksi.nomor_struk,
        subtotal=subtotal_simpan,
        diskon_member=diskon_member_out,
        diskon_promo=diskon_promo_out,
        diskon_poin=diskon_poin_out,
        total_diskon=diskon_simpan,
        service=service_out,
        rincian_service=rincian_service_out,
        total_pajak=_m(pajak_simpan - service_out),
        rincian_pajak=rincian_pajak_out,
        pembulatan=pembulatan_simpan,
        total=total_simpan,
        total_bayar=transaksi.total_bayar,
        kembalian=transaksi.kembalian,
        status=transaksi.status,
        status_bayar=transaksi.status_bayar,
        sisa_tagihan=transaksi.sisa_tagihan,
        jatuh_tempo=transaksi.jatuh_tempo,
    )


async def _ke_checkout_out(db: AsyncSession, transaksi: Transaksi) -> CheckoutOut:
    """Jalur idempotency (body.id sudah ada) - transaksi TIDAK dihitung
    ulang, baris yang sudah tersimpan dibaca kembali apa adanya. Rincian
    pajak vs service dibedakan lewat join ke Pajak.tipe (transaksi_pajak
    sendiri tidak punya kolom tipe) - kosong utk transaksi yang berasal
    dari push offline (tidak menulis baris rincian, lihat checkout())."""

    rincian_rows = (
        await db.execute(
            select(TransaksiPajak, Pajak.tipe)
            .outerjoin(Pajak, Pajak.id == TransaksiPajak.pajak_id)
            .where(TransaksiPajak.transaksi_id == transaksi.id)
        )
    ).all()
    rincian_pajak = [RincianPajakOut(nama=r.nama, persen=r.persen, jumlah=r.jumlah) for r, tipe in rincian_rows if tipe != "service"]
    rincian_service = [RincianServiceOut(nama=r.nama, persen=r.persen, jumlah=r.jumlah) for r, tipe in rincian_rows if tipe == "service"]
    service = sum((r.jumlah for r in rincian_service), Decimal("0"))

    promo_rows = (
        await db.execute(select(TransaksiPromo).where(TransaksiPromo.transaksi_id == transaksi.id))
    ).scalars().all()
    # "Tukar poin" dibedakan dari "Diskon member" lewat nama (keduanya
    # sama2 promo_id=None, bukan promo sungguhan) - lihat checkout() soal
    # kenapa dipakai sentinel nama drpd kolom/tabel baru (hindari migrasi).
    diskon_member = sum(
        (p.jumlah_diskon for p in promo_rows if p.promo_id is None and p.nama != "Tukar poin"), Decimal("0")
    )
    diskon_promo = sum((p.jumlah_diskon for p in promo_rows if p.promo_id is not None), Decimal("0"))
    diskon_poin = sum(
        (p.jumlah_diskon for p in promo_rows if p.promo_id is None and p.nama == "Tukar poin"), Decimal("0")
    )

    return CheckoutOut(
        id=transaksi.id,
        nomor_struk=transaksi.nomor_struk,
        subtotal=transaksi.subtotal,
        diskon_member=diskon_member,
        diskon_promo=diskon_promo,
        diskon_poin=diskon_poin,
        total_diskon=transaksi.total_diskon,
        service=service,
        rincian_service=rincian_service,
        total_pajak=transaksi.total_pajak - service,
        rincian_pajak=rincian_pajak,
        pembulatan=transaksi.pembulatan,
        total=transaksi.total,
        total_bayar=transaksi.total_bayar,
        kembalian=transaksi.kembalian,
        status=transaksi.status,
        status_bayar=transaksi.status_bayar,
        sisa_tagihan=transaksi.sisa_tagihan,
        jatuh_tempo=transaksi.jatuh_tempo,
    )
