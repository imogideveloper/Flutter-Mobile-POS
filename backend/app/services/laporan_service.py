"""Laporan - agregasi murni dari data transaksi/item_transaksi/pembayaran
yang sudah ada, TIDAK ada tabel baru. Pola hitungnya sengaja dibuat sama
dengan `LaporanRepository` di app Flutter (lib/features/laporan/data/
laporan_repository.dart) supaya "penjualan bersih"/"laba kotor"/dst
berarti hal yang sama di kedua sisi, walau datanya beda (app = data lokal
HP, sini = agregat lintas-outlet/toko dari server)."""

import uuid
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from decimal import Decimal

from fastapi import HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.pelanggan import Pelanggan
from app.models.transaksi import ItemRefund, ItemTransaksi, MetodeBayar, Pembayaran, Refund, Shift, Transaksi
from app.schemas.laporan import (
    JamRamaiOut,
    LaporanPiutangOut,
    LaporanShiftOut,
    MetodeBayarPersenOut,
    PiutangPelangganOut,
    ProdukTerlarisOut,
    RingkasanPenjualanOut,
)
from app.services.fitur_service import batas_fitur_toko
from app.services.shift_service import hitung_kas_seharusnya


async def pastikan_rentang_diizinkan(
    db: AsyncSession, *, toko_id: uuid.UUID, dari: datetime, sampai: datetime
) -> None:
    """`laporan_dasar` adalah fitur tingkat 0 (semua paket dapat), TAPI
    `paket_fitur.batas` membatasi SEBERAPA JAUH ke belakang (hari) rentang
    `dari` boleh diminta - Gratis 30 hari, Pro 365 hari, Bisnis tanpa
    batas (lihat migrasi 0002). Ini BUKAN require_fitur (fitur-nya tetap
    terbuka utk semua) - makanya 422 (rentang tidak valid), bukan 403."""

    batas_hari = await batas_fitur_toko(db, toko_id, "laporan_dasar")
    if batas_hari is None:
        return

    now = datetime.now(UTC)
    paling_lama = now - timedelta(days=batas_hari)
    dari_bandingkan = dari if dari.tzinfo is not None else dari.replace(tzinfo=UTC)
    if dari_bandingkan < paling_lama:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail={
                "kode": "rentang_laporan_melebihi_batas",
                "batas_hari": batas_hari,
                "pesan": f"Paket toko ini cuma bisa lihat laporan {batas_hari} hari ke belakang - upgrade paket utk rentang lebih jauh",
            },
        )


async def _transaksi_selesai(
    db: AsyncSession, toko_id: uuid.UUID, outlet_id: uuid.UUID | None, dari: datetime, sampai: datetime
) -> list[Transaksi]:
    query = select(Transaksi).where(
        Transaksi.toko_id == toko_id,
        Transaksi.status == "selesai",
        Transaksi.tanggal >= dari,
        Transaksi.tanggal < sampai,
    )
    if outlet_id is not None:
        query = query.where(Transaksi.outlet_id == outlet_id)
    return list((await db.execute(query)).scalars().all())


_DUA_DESIMAL = Decimal("0.01")


@dataclass(frozen=True)
class PenjualanTransaksi:
    """Satu transaksi yang dihitung sebagai penjualan, beserta total refund yang sudah dikembalikan.

    Keputusan sementara AT1 (docs/perlu_konfirmasi.md), selaras dengan app Flutter
    (lib/features/laporan/domain/angka_penjualan.dart): penjualan bersih = tanpa pajak, service, dan
    pembulatan; total penerimaan = semua uang dari pelanggan; refund dikurangkan proporsional."""

    transaksi: Transaksi
    refund: Decimal

    @property
    def sisa(self) -> Decimal:
        """Bagian transaksi yang masih penjualan (1 = utuh, 0 = semuanya sudah direfund)."""
        total = Decimal(self.transaksi.total)
        if total <= 0:
            return Decimal("1")
        return max(Decimal("0"), Decimal("1") - min(self.refund, total) / total)

    @property
    def penjualan_bersih(self) -> Decimal:
        t = self.transaksi
        dasar = Decimal(t.total) - Decimal(t.total_pajak) - Decimal(t.pembulatan)
        return (dasar * self.sisa).quantize(_DUA_DESIMAL)

    @property
    def pajak_service(self) -> Decimal:
        return (Decimal(self.transaksi.total_pajak) * self.sisa).quantize(_DUA_DESIMAL)

    @property
    def total_penerimaan(self) -> Decimal:
        total = Decimal(self.transaksi.total)
        if total <= 0:
            return total.quantize(_DUA_DESIMAL)
        return (total - min(self.refund, total)).quantize(_DUA_DESIMAL)


async def transaksi_penjualan(
    db: AsyncSession, toko_id: uuid.UUID, outlet_id: uuid.UUID | None, dari: datetime, sampai: datetime
) -> list[PenjualanTransaksi]:
    """Transaksi yang dihitung sebagai penjualan: selesai dan refund sebagian (sisanya masih penjualan).
    Refund penuh dan void tidak ikut. Bandingkan `_transaksi_selesai` yang hanya status selesai."""
    query = select(Transaksi).where(
        Transaksi.toko_id == toko_id,
        Transaksi.status.in_(("selesai", "refund_sebagian")),
        Transaksi.tanggal >= dari,
        Transaksi.tanggal < sampai,
    )
    if outlet_id is not None:
        query = query.where(Transaksi.outlet_id == outlet_id)
    transaksi_list = list((await db.execute(query)).scalars().all())
    if not transaksi_list:
        return []

    rows = await db.execute(
        select(Refund.transaksi_id, func.coalesce(func.sum(Refund.total), 0))
        .where(Refund.transaksi_id.in_([t.id for t in transaksi_list]), Refund.deleted_at.is_(None))
        .group_by(Refund.transaksi_id)
    )
    refund_per_transaksi = {tid: Decimal(str(jumlah)) for tid, jumlah in rows.all()}
    return [PenjualanTransaksi(t, refund_per_transaksi.get(t.id, Decimal("0"))) for t in transaksi_list]


@dataclass(frozen=True)
class ItemPenjualan:
    """Item transaksi dengan qty yang masih terjual. `qty_hpp` = qty yang HPP-nya tetap ditanggung
    (barang yang direfund tetapi tidak dikembalikan ke stok tetap jadi biaya)."""

    item: ItemTransaksi
    qty: Decimal
    qty_hpp: Decimal

    @property
    def subtotal(self) -> Decimal:
        qty_asli = Decimal(self.item.qty)
        if qty_asli <= 0:
            return Decimal("0")
        return (Decimal(self.item.subtotal) * self.qty / qty_asli).quantize(_DUA_DESIMAL)


async def item_penjualan(db: AsyncSession, transaksi_ids: list[uuid.UUID]) -> list[ItemPenjualan]:
    """Item untuk [transaksi_ids] setelah dikurangi qty yang sudah direfund (dari `item_refund`)."""
    items = await _item_untuk_transaksi(db, transaksi_ids)
    if not items:
        return []
    rows = await db.execute(
        select(ItemRefund.item_transaksi_id, ItemRefund.qty, Refund.kembalikan_stok)
        .join(Refund, Refund.id == ItemRefund.refund_id)
        .where(
            Refund.transaksi_id.in_(transaksi_ids),
            Refund.deleted_at.is_(None),
            ItemRefund.deleted_at.is_(None),
        )
    )
    direfund: dict[uuid.UUID, Decimal] = {}
    direfund_stok: dict[uuid.UUID, Decimal] = {}
    for item_id, qty, kembalikan_stok in rows.all():
        direfund[item_id] = direfund.get(item_id, Decimal("0")) + Decimal(str(qty))
        if kembalikan_stok:
            direfund_stok[item_id] = direfund_stok.get(item_id, Decimal("0")) + Decimal(str(qty))
    return [
        ItemPenjualan(
            item=i,
            qty=max(Decimal("0"), Decimal(i.qty) - direfund.get(i.id, Decimal("0"))),
            qty_hpp=max(Decimal("0"), Decimal(i.qty) - direfund_stok.get(i.id, Decimal("0"))),
        )
        for i in items
    ]


async def _item_untuk_transaksi(db: AsyncSession, transaksi_ids: list[uuid.UUID]) -> list[ItemTransaksi]:
    if not transaksi_ids:
        return []
    return list(
        (await db.execute(select(ItemTransaksi).where(ItemTransaksi.transaksi_id.in_(transaksi_ids))))
        .scalars()
        .all()
    )


async def _pembayaran_untuk_transaksi(db: AsyncSession, transaksi_ids: list[uuid.UUID]) -> list[Pembayaran]:
    if not transaksi_ids:
        return []
    return list(
        (await db.execute(select(Pembayaran).where(Pembayaran.transaksi_id.in_(transaksi_ids))))
        .scalars()
        .all()
    )


async def _label_metode_bayar(db: AsyncSession, toko_id: uuid.UUID) -> dict[uuid.UUID, str]:
    rows = (await db.execute(select(MetodeBayar).where(MetodeBayar.toko_id == toko_id))).scalars().all()
    return {r.id: r.nama for r in rows}


def _label_pembayaran(nama_metode: str, payload_gateway: dict | None) -> str:
    """Temuan A.1 (tahap 5) - QRIS statis/manual (dikonfirmasi kasir lihat
    layar HP sendiri, BUKAN webhook payment gateway sungguhan) ditandai
    terpisah di laporan supaya owner tahu baris ini belum benar2
    terverifikasi pihak ketiga - lihat BayarQrisPage._payloadKonfirmasiManual
    di sisi Flutter utk asal marker ini."""
    dasar = nama_metode
    if payload_gateway and payload_gateway.get("metode") == "qris_statis_manual":
        dasar = "QRIS manual (belum terverifikasi)"
    # Label tujuan (IMOGI no. 18, mis. GoPay/OVO/BCA): baris dipisah per tujuan supaya bisa
    # direkonsiliasi dengan mutasi/settlement masing-masing. Dart mirror: laporan_repository.dart.
    # Kartu: jenis (Debit/Kredit) lebih dulu, lalu mesin EDC/tujuan, mis. "Kartu · Debit · EDC BCA".
    bagian: list[str] = []
    if payload_gateway:
        jenis = {"debit": "Debit", "kredit": "Kredit"}.get(payload_gateway.get("jenis_kartu"))
        if jenis:
            bagian.append(jenis)
        tujuan = payload_gateway.get("label_tujuan")
        if isinstance(tujuan, str) and tujuan.strip():
            bagian.append(tujuan.strip())
    return " · ".join([dasar, *bagian])


async def _kas_diterima_periode(
    db: AsyncSession, *, toko_id: uuid.UUID, outlet_id: uuid.UUID | None, dari: datetime, sampai: datetime
) -> Decimal:
    """Uang yang BENAR2 masuk selama periode ini (tahap 3b-1 aturan #6) -
    disaring pakai `coalesce(dibayar_pada, created_at)` MILIK PEMBAYARAN
    itu sendiri (bukan tanggal transaksinya) supaya cicilan/pelunasan
    kasbon yang dibayar belakangan ikut terhitung di periode saat uangnya
    diterima, bukan di periode saat transaksinya dibuat - beda dari
    `penjualan_bersih` yang menghitung nilai transaksi yg TERJADI di
    periode ini, berapa pun yang sudah/belum dibayar."""

    query = (
        select(func.coalesce(func.sum(Pembayaran.jumlah), 0))
        .join(Transaksi, Transaksi.id == Pembayaran.transaksi_id)
        .where(
            Transaksi.toko_id == toko_id,
            Pembayaran.status == "berhasil",
            func.coalesce(Pembayaran.dibayar_pada, Pembayaran.created_at) >= dari,
            func.coalesce(Pembayaran.dibayar_pada, Pembayaran.created_at) < sampai,
        )
    )
    if outlet_id is not None:
        query = query.where(Transaksi.outlet_id == outlet_id)
    total = await db.scalar(query)
    return Decimal(str(total or 0))


async def ringkasan_penjualan(
    db: AsyncSession,
    *,
    toko_id: uuid.UUID,
    outlet_id: uuid.UUID | None,
    dari: datetime,
    sampai: datetime,
) -> RingkasanPenjualanOut:
    # Penjualan = selesai + refund sebagian, dikurangi refund (AT1); refund penuh dan void tidak ikut.
    penjualan_list = await transaksi_penjualan(db, toko_id, outlet_id, dari, sampai)
    transaksi_ids = [p.transaksi.id for p in penjualan_list]

    items = await item_penjualan(db, transaksi_ids)
    pembayaran_list = await _pembayaran_untuk_transaksi(db, transaksi_ids)
    label_metode = await _label_metode_bayar(db, toko_id)
    kas_diterima = await _kas_diterima_periode(
        db, toko_id=toko_id, outlet_id=outlet_id, dari=dari, sampai=sampai
    )

    nol = Decimal("0")
    penjualan_bersih = sum((p.penjualan_bersih for p in penjualan_list), nol)
    pajak_service = sum((p.pajak_service for p in penjualan_list), nol)
    total_penerimaan = sum((p.total_penerimaan for p in penjualan_list), nol)
    laba_kotor = sum(
        (
            (i.item.harga_satuan * i.qty - i.item.hpp_satuan * i.qty_hpp)
            for i in items
        ),
        nol,
    )
    jumlah_transaksi = len(penjualan_list)
    rata_rata = (penjualan_bersih / jumlah_transaksi) if jumlah_transaksi else nol

    jam_total: dict[int, Decimal] = {}
    for p in penjualan_list:
        jam = p.transaksi.tanggal.hour
        jam_total[jam] = jam_total.get(jam, nol) + p.penjualan_bersih
    jam_ramai = [JamRamaiOut(jam=jam, total=total) for jam, total in sorted(jam_total.items())]

    # Key (metode_bayar_id, label) - BUKAN cuma metode_bayar_id - supaya
    # QRIS manual/belum terverifikasi (lihat _label_pembayaran) selalu
    # muncul sbg baris TERPISAH dari QRIS yang sungguhan terverifikasi,
    # walau metode_bayar_id-nya sama persis.
    metode_total: dict[tuple[uuid.UUID, str], Decimal] = {}
    for p in pembayaran_list:
        label = _label_pembayaran(label_metode.get(p.metode_bayar_id, "-"), p.payload_gateway)
        key = (p.metode_bayar_id, label)
        metode_total[key] = metode_total.get(key, Decimal("0")) + p.jumlah
    total_semua_metode = sum(metode_total.values(), Decimal("0"))
    metode_bayar = sorted(
        (
            MetodeBayarPersenOut(
                metode_bayar_id=mid,
                nama=label,
                total=total,
                persen=(total / total_semua_metode * 100) if total_semua_metode else Decimal("0"),
            )
            for (mid, label), total in metode_total.items()
        ),
        key=lambda m: m.total,
        reverse=True,
    )

    return RingkasanPenjualanOut(
        penjualan_bersih=penjualan_bersih,
        pajak_service=pajak_service,
        total_penerimaan=total_penerimaan,
        kas_diterima=kas_diterima,
        laba_kotor=laba_kotor,
        jumlah_transaksi=jumlah_transaksi,
        rata_rata=rata_rata,
        jam_ramai=jam_ramai,
        metode_bayar=metode_bayar,
    )


async def produk_terlaris(
    db: AsyncSession,
    *,
    toko_id: uuid.UUID,
    outlet_id: uuid.UUID | None,
    dari: datetime,
    sampai: datetime,
    limit: int = 5,
) -> list[ProdukTerlarisOut]:
    penjualan_list = await transaksi_penjualan(db, toko_id, outlet_id, dari, sampai)
    items = await item_penjualan(db, [p.transaksi.id for p in penjualan_list])

    agregat: dict[uuid.UUID, dict] = {}
    for ip in items:
        if ip.qty <= 0:
            continue  # seluruh qty item ini sudah direfund
        item = ip.item
        entry = agregat.setdefault(
            item.produk_id, {"nama_produk": item.nama_produk, "qty": Decimal("0"), "total": Decimal("0")}
        )
        entry["qty"] += ip.qty
        entry["total"] += ip.subtotal

    hasil = sorted(
        (ProdukTerlarisOut(produk_id=pid, **data) for pid, data in agregat.items()),
        key=lambda p: p.total,
        reverse=True,
    )
    return hasil[:limit]


async def piutang(
    db: AsyncSession, *, toko_id: uuid.UUID, outlet_id: uuid.UUID | None
) -> LaporanPiutangOut:
    """Laporan piutang (tahap 3b-1 aturan #6) - snapshot KONDISI SEKARANG
    (bukan laporan bertanggal seperti laporan/penjualan), per pelanggan:
    total utang (sum sisa_tagihan transaksi kasbon yang belum lunas),
    jatuh tempo TERDEKAT di antara transaksi2 itu, dan umur piutang
    (hari sejak jatuh tempo terdekat itu lewat, 0 kalau belum lewat) -
    app yang mengelompokkan umur_hari itu ke bucket 0-30/31-60/>60,
    server cuma kirim angka mentahnya."""

    query = select(Transaksi).where(
        Transaksi.toko_id == toko_id,
        Transaksi.status == "selesai",
        Transaksi.status_bayar != "lunas",
        Transaksi.pelanggan_id.is_not(None),
        Transaksi.deleted_at.is_(None),
    )
    if outlet_id is not None:
        query = query.where(Transaksi.outlet_id == outlet_id)
    transaksi_list = list((await db.execute(query)).scalars().all())

    pelanggan_ids = {t.pelanggan_id for t in transaksi_list}
    label_pelanggan: dict[uuid.UUID, str] = {}
    if pelanggan_ids:
        rows = (
            await db.execute(select(Pelanggan).where(Pelanggan.id.in_(pelanggan_ids)))
        ).scalars().all()
        label_pelanggan = {r.id: r.nama for r in rows}

    agregat: dict[uuid.UUID, dict] = {}
    for t in transaksi_list:
        entry = agregat.setdefault(
            t.pelanggan_id,
            {"total_utang": Decimal("0"), "jumlah_transaksi": 0, "jatuh_tempo_terdekat": None},
        )
        entry["total_utang"] += Decimal(str(t.sisa_tagihan or 0))
        entry["jumlah_transaksi"] += 1
        if t.jatuh_tempo is not None and (
            entry["jatuh_tempo_terdekat"] is None or t.jatuh_tempo < entry["jatuh_tempo_terdekat"]
        ):
            entry["jatuh_tempo_terdekat"] = t.jatuh_tempo

    hari_ini = datetime.now(UTC).date()
    pelanggan_out: list[PiutangPelangganOut] = []
    for pelanggan_id, data in agregat.items():
        jatuh_tempo_terdekat = data["jatuh_tempo_terdekat"]
        lewat = jatuh_tempo_terdekat is not None and jatuh_tempo_terdekat < hari_ini
        umur_hari = (hari_ini - jatuh_tempo_terdekat).days if lewat else 0
        pelanggan_out.append(
            PiutangPelangganOut(
                pelanggan_id=pelanggan_id,
                nama_pelanggan=label_pelanggan.get(pelanggan_id, "-"),
                total_utang=data["total_utang"],
                jumlah_transaksi=data["jumlah_transaksi"],
                jatuh_tempo_terdekat=jatuh_tempo_terdekat,
                lewat_jatuh_tempo=lewat,
                umur_hari=umur_hari,
            )
        )
    pelanggan_out.sort(key=lambda p: p.total_utang, reverse=True)

    return LaporanPiutangOut(
        total_piutang=sum((p.total_utang for p in pelanggan_out), Decimal("0")),
        jumlah_pelanggan=len(pelanggan_out),
        jumlah_lewat_jatuh_tempo=sum(1 for p in pelanggan_out if p.lewat_jatuh_tempo),
        pelanggan=pelanggan_out,
    )


async def laporan_shift(db: AsyncSession, *, toko_id: uuid.UUID, shift: Shift) -> LaporanShiftOut:
    transaksi_list = (
        await db.execute(
            select(Transaksi).where(Transaksi.shift_id == shift.id, Transaksi.status == "selesai")
        )
    ).scalars().all()
    transaksi_ids = [t.id for t in transaksi_list]

    pembayaran_list = await _pembayaran_untuk_transaksi(db, transaksi_ids)
    label_metode = await _label_metode_bayar(db, toko_id)

    penjualan_bersih = sum((t.total for t in transaksi_list), Decimal("0"))

    metode_total: dict[tuple[uuid.UUID, str], Decimal] = {}
    for p in pembayaran_list:
        label = _label_pembayaran(label_metode.get(p.metode_bayar_id, "-"), p.payload_gateway)
        key = (p.metode_bayar_id, label)
        metode_total[key] = metode_total.get(key, Decimal("0")) + p.jumlah
    total_semua_metode = sum(metode_total.values(), Decimal("0"))
    metode_bayar = sorted(
        (
            MetodeBayarPersenOut(
                metode_bayar_id=mid,
                nama=label,
                total=total,
                persen=(total / total_semua_metode * 100) if total_semua_metode else Decimal("0"),
            )
            for (mid, label), total in metode_total.items()
        ),
        key=lambda m: m.total,
        reverse=True,
    )

    kas_seharusnya = shift.kas_seharusnya
    if kas_seharusnya is None and shift.status == "buka":
        # Shift masih berjalan - hitung proyeksi kas seharusnya sampai saat
        # ini (bukan nilai final, itu baru dikunci saat tutup_shift).
        kas_seharusnya = await hitung_kas_seharusnya(db, shift.id, shift.modal_awal)

    return LaporanShiftOut(
        shift_id=shift.id,
        status=shift.status,
        modal_awal=shift.modal_awal,
        kas_seharusnya=kas_seharusnya,
        kas_aktual=shift.kas_aktual,
        selisih=shift.selisih,
        jumlah_transaksi=len(transaksi_list),
        penjualan_bersih=penjualan_bersih,
        metode_bayar=metode_bayar,
    )
