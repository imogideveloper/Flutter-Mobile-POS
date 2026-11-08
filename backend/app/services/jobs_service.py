"""Logika job latar belakang - DIPISAH dari app/jobs/arq_worker.py supaya
bisa dites langsung lewat pytest tanpa butuh Redis/ARQ sungguhan (sandbox
ini tidak punya Redis - lihat README bagian Keterbatasan). arq_worker.py
hanya pembungkus tipis yang mendaftarkan fungsi2 ini ke ARQ cron."""

from datetime import UTC, datetime, timedelta

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.audit import Notifikasi
from app.models.outlet import Langganan, Outlet, Toko
from app.services.fitur_service import paket_tertinggi, trial_toko
from app.services.platform_service import (
    DEFAULT_TRIAL_NOTIFIKASI_HARI,
    KUNCI_TRIAL_NOTIFIKASI_HARI,
    KUNCI_USIA_AKUN_BULAN,
    ambil_int,
)
from app.models.stok import Stok
from app.models.transaksi import Transaksi


async def tandai_langganan_kedaluwarsa(db: AsyncSession) -> int:
    """Langganan aktif yang `berakhir`-nya sudah lewat ditandai
    'kedaluwarsa' + dikirim notifikasi ke toko-nya. Langganan tanpa
    `berakhir` (NULL = tidak terbatas, mis. paket Gratis) tidak pernah
    disentuh job ini."""

    now = datetime.now(UTC)
    rows = (
        await db.execute(
            select(Langganan).where(
                Langganan.status == "aktif", Langganan.berakhir.is_not(None), Langganan.berakhir < now
            )
        )
    ).scalars().all()

    for langganan in rows:
        langganan.status = "kedaluwarsa"
        db.add(
            Notifikasi(
                toko_id=langganan.toko_id,
                jenis="langganan",
                judul="Paket langganan sudah kedaluwarsa",
                isi="Perpanjang langganan supaya fitur berbayar tetap aktif.",
                ref_tipe="langganan",
                ref_id=langganan.id,
            )
        )

    await db.commit()
    return len(rows)


async def cek_trial_hampir_berakhir_dan_notifikasi(db: AsyncSession) -> int:
    """Notifikasi SEKALI per toko saat masa trial (berdasarkan usia akun)
    tinggal `trial_notifikasi_hari` hari (awal 7) atau kurang. Tidak
    dikirim ulang untuk toko yang sudah pernah dapat (dedupe lewat
    ref_tipe='trial' + ref_id=toko_id), dan tidak dikirim bila trial mati
    atau sudah berakhir."""

    if await ambil_int(db, KUNCI_USIA_AKUN_BULAN, 0) <= 0:
        return 0
    batas_hari = await ambil_int(db, KUNCI_TRIAL_NOTIFIKASI_HARI, DEFAULT_TRIAL_NOTIFIKASI_HARI)

    dibuat = 0
    for toko_id in (await db.execute(select(Toko.id))).scalars().all():
        trial = await trial_toko(db, toko_id)
        if trial is None or not trial.aktif or trial.hari_tersisa > batas_hari:
            continue
        sudah_ada = await db.scalar(
            select(Notifikasi).where(Notifikasi.ref_tipe == "trial", Notifikasi.ref_id == toko_id)
        )
        if sudah_ada is not None:
            continue

        tertinggi = await paket_tertinggi(db)
        nama_paket = tertinggi.nama if tertinggi is not None else "berbayar"
        db.add(
            Notifikasi(
                toko_id=toko_id,
                jenis="langganan",
                judul=f"Free trial paket {nama_paket} berakhir dalam {trial.hari_tersisa} hari",
                isi=f"Batas berakhir: {trial.berakhir:%d-%m-%Y}. Pilih paket supaya fitur tetap aktif.",
                ref_tipe="trial",
                ref_id=toko_id,
            )
        )
        dibuat += 1

    await db.commit()
    return dibuat


async def cek_stok_menipis_dan_notifikasi(db: AsyncSession) -> int:
    """Stok yang jumlahnya <= batas_minimum (batas_minimum > 0, supaya
    produk yang memang belum diatur batasnya tidak mengganggu) dikirim
    SATU notifikasi tak terbaca - tidak dikirim ulang selama notifikasi
    sebelumnya utk stok yang sama belum dibaca (`dibaca_pada IS NULL`),
    supaya owner tidak dibanjiri notifikasi duplikat tiap job jalan."""

    rows = (
        await db.execute(select(Stok).where(Stok.batas_minimum > 0, Stok.jumlah <= Stok.batas_minimum))
    ).scalars().all()

    dibuat = 0
    for stok in rows:
        sudah_ada = await db.scalar(
            select(Notifikasi).where(
                Notifikasi.ref_tipe == "stok", Notifikasi.ref_id == stok.id, Notifikasi.dibaca_pada.is_(None)
            )
        )
        if sudah_ada is not None:
            continue

        outlet = await db.get(Outlet, stok.outlet_id)
        if outlet is None:
            continue

        db.add(
            Notifikasi(
                toko_id=outlet.toko_id,
                jenis="stok_menipis",
                judul="Stok menipis",
                isi=f"Sisa {stok.jumlah} - sudah di bawah batas minimum {stok.batas_minimum}.",
                ref_tipe="stok",
                ref_id=stok.id,
            )
        )
        dibuat += 1

    await db.commit()
    return dibuat


async def cek_kasbon_jatuh_tempo_dan_notifikasi(db: AsyncSession) -> int:
    """Harian (tahap 3b-1 aturan #7): notifikasi owner utk kasbon yang
    jatuh tempo BESOK (pengingat dini) dan yang SUDAH LEWAT (tagihan
    telat) - dua `jenis` notifikasi TERPISAH krn satu transaksi yang sama
    wajar kena keduanya di hari yang berbeda (besok dulu, lalu lewat
    begitu hari H lewat tanpa dibayar). Sama pola dgn
    cek_stok_menipis_dan_notifikasi: tidak dikirim ulang selama notifikasi
    SEJENIS utk ref yang sama belum dibaca - supaya owner tidak dibanjiri
    notifikasi duplikat tiap job jalan tiap hari selama piutang itu belum
    dilunasi/dibaca."""

    hari_ini = datetime.now(UTC).date()
    besok = hari_ini + timedelta(days=1)

    rows = (
        await db.execute(
            select(Transaksi).where(
                Transaksi.status == "selesai",
                Transaksi.status_bayar != "lunas",
                Transaksi.jatuh_tempo.is_not(None),
                Transaksi.deleted_at.is_(None),
            )
        )
    ).scalars().all()

    dibuat = 0
    for t in rows:
        if t.jatuh_tempo == besok:
            jenis = "kasbon_jatuh_tempo_besok"
            judul = "Kasbon jatuh tempo besok"
            isi = f"Transaksi {t.nomor_struk} (sisa {t.sisa_tagihan}) jatuh tempo besok ({t.jatuh_tempo})."
        elif t.jatuh_tempo < hari_ini:
            jenis = "kasbon_jatuh_tempo_lewat"
            judul = "Kasbon sudah lewat jatuh tempo"
            isi = f"Transaksi {t.nomor_struk} (sisa {t.sisa_tagihan}) sudah lewat jatuh tempo ({t.jatuh_tempo})."
        else:
            continue

        sudah_ada = await db.scalar(
            select(Notifikasi).where(
                Notifikasi.jenis == jenis,
                Notifikasi.ref_tipe == "transaksi",
                Notifikasi.ref_id == t.id,
                Notifikasi.dibaca_pada.is_(None),
            )
        )
        if sudah_ada is not None:
            continue

        db.add(
            Notifikasi(
                toko_id=t.toko_id, jenis=jenis, judul=judul, isi=isi, ref_tipe="transaksi", ref_id=t.id,
            )
        )
        dibuat += 1

    await db.commit()
    return dibuat
