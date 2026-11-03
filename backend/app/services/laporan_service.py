"""Laporan - agregasi murni dari data transaksi/item_transaksi/pembayaran
yang sudah ada, TIDAK ada tabel baru. Pola hitungnya sengaja dibuat sama
dengan `LaporanRepository` di app Flutter (lib/features/laporan/data/
laporan_repository.dart) supaya "penjualan bersih"/"laba kotor"/dst
berarti hal yang sama di kedua sisi, walau datanya beda (app = data lokal
HP, sini = agregat lintas-outlet/toko dari server)."""

import uuid
from datetime import UTC, datetime, timedelta
from decimal import Decimal

from fastapi import HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.pelanggan import Pelanggan
from app.models.transaksi import ItemTransaksi, MetodeBayar, Pembayaran, Shift, Transaksi
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
    if payload_gateway and payload_gateway.get("metode") == "qris_statis_manual":
        return "QRIS manual (belum terverifikasi)"
    return nama_metode


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
    transaksi_list = await _transaksi_selesai(db, toko_id, outlet_id, dari, sampai)
    transaksi_ids = [t.id for t in transaksi_list]

    items = await _item_untuk_transaksi(db, transaksi_ids)
    pembayaran_list = await _pembayaran_untuk_transaksi(db, transaksi_ids)
    label_metode = await _label_metode_bayar(db, toko_id)
    kas_diterima = await _kas_diterima_periode(
        db, toko_id=toko_id, outlet_id=outlet_id, dari=dari, sampai=sampai
    )

    penjualan_bersih = sum((t.total for t in transaksi_list), Decimal("0"))
    laba_kotor = sum(
        ((item.harga_satuan - item.hpp_satuan) * item.qty for item in items), Decimal("0")
    )
    jumlah_transaksi = len(transaksi_list)
    rata_rata = (penjualan_bersih / jumlah_transaksi) if jumlah_transaksi else Decimal("0")

    jam_total: dict[int, Decimal] = {}
    for t in transaksi_list:
        jam = t.tanggal.hour
        jam_total[jam] = jam_total.get(jam, Decimal("0")) + t.total
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
    transaksi_list = await _transaksi_selesai(db, toko_id, outlet_id, dari, sampai)
    items = await _item_untuk_transaksi(db, [t.id for t in transaksi_list])

    agregat: dict[uuid.UUID, dict] = {}
    for item in items:
        entry = agregat.setdefault(
            item.produk_id, {"nama_produk": item.nama_produk, "qty": Decimal("0"), "total": Decimal("0")}
        )
        entry["qty"] += item.qty
        entry["total"] += item.subtotal

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
