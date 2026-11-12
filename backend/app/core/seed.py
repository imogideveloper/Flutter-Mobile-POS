"""Seed data dasar (role bawaan + izin) lewat ORM - dipakai fixture pytest
SAJA. Migrasi 0001 (Postgres produksi) punya seed-nya sendiri sebagai SQL
mentah (termasuk paket/fitur/role/izin) - dua jalur ini SENGAJA terpisah
(bukan dibuat baca dari sini) karena migrasi 0001 harus tetap jadi DDL
"apa adanya" dari dokumen sumber kebenaran. Helper ini hanya meniru subset
yang dibutuhkan test (role + izin + role_izin), bukan seluruh seed produksi."""

from sqlalchemy.ext.asyncio import AsyncSession

from app.models.akun import Izin, Role, RoleIzin
from app.models.fitur import Fitur, PaketFitur
from app.models.outlet import Paket

_IZIN = [
    ("transaksi.buat", "penjualan", "Membuat transaksi"),
    ("transaksi.diskon", "penjualan", "Memberi diskon manual"),
    ("transaksi.void", "penjualan", "Membatalkan transaksi"),
    ("transaksi.refund", "penjualan", "Melakukan refund"),
    ("transaksi.batal_pesanan", "penjualan", "Approval batalkan pesanan tersimpan"),
    ("shift.buka_tutup", "penjualan", "Membuka dan menutup shift"),
    ("kas.keluar_masuk", "penjualan", "Mencatat kas keluar/masuk"),
    ("produk.kelola", "produk", "Tambah/ubah/hapus produk"),
    ("stok.kelola", "stok", "Stok masuk, opname, transfer"),
    ("pembelian.kelola", "stok", "Mengelola pembelian supplier"),
    ("pelanggan.kelola", "penjualan", "Mengelola data pelanggan"),
    ("promo.kelola", "penjualan", "Mengelola promo dan pajak"),
    ("laporan.lihat", "laporan", "Melihat laporan"),
    ("pengguna.kelola", "pengaturan", "Mengelola karyawan dan role"),
    ("pengaturan.kelola", "pengaturan", "Mengubah pengaturan toko/outlet"),
]

_KASIR_IZIN = {"transaksi.buat", "shift.buka_tutup", "kas.keluar_masuk", "pelanggan.kelola"}
_MANAJER_KECUALI = {"pengguna.kelola", "pengaturan.kelola"}


async def seed_role_izin(db: AsyncSession) -> None:
    izin_rows = {kode: Izin(kode=kode, modul=modul, deskripsi=deskripsi) for kode, modul, deskripsi in _IZIN}
    db.add_all(izin_rows.values())
    await db.flush()

    owner = Role(nama="Owner", is_system=True)
    manajer = Role(nama="Manajer", is_system=True)
    kasir = Role(nama="Kasir", is_system=True)
    db.add_all([owner, manajer, kasir])
    await db.flush()

    for kode, izin in izin_rows.items():
        db.add(RoleIzin(role_id=owner.id, izin_id=izin.id))
        if kode not in _MANAJER_KECUALI:
            db.add(RoleIzin(role_id=manajer.id, izin_id=izin.id))
        if kode in _KASIR_IZIN:
            db.add(RoleIzin(role_id=kasir.id, izin_id=izin.id))

    await db.commit()


# 32 fitur resmi - disalin PERSIS (kode/nama/modul/tingkat) dari seed SQL
# mentah di migrasi 0001 (`INSERT INTO fitur ...`), supaya perilaku gating
# yang dites lewat fixture SQLite ini identik dgn yang bakal jalan di
# Postgres produksi - sebelumnya cuma 11 dari 32 (subset), yang berarti
# gating fitur2 lain TIDAK PERNAH bisa dites sama sekali lewat fixture ini.
_FITUR = [
    ("pos", "Kasir (POS)", "penjualan", 0),
    ("cetak_struk", "Cetak struk", "penjualan", 0),
    ("scan_barcode", "Scan produk", "produk", 0),
    ("kelola_stok", "Kelola stok produk", "stok", 0),
    ("kelola_pelanggan", "Kelola pelanggan", "pelanggan", 0),
    ("laporan_dasar", "Laporan penjualan", "laporan", 0),
    ("qris", "Pembayaran QRIS", "penjualan", 1),
    ("kasbon", "Bayar dengan utang (kasbon)", "penjualan", 1),
    ("tren_penjualan", "Tren penjualan", "laporan", 1),
    ("multi_outlet", "Multi-outlet (biaya per outlet)", "bisnis", 1),
    ("resep", "Bahan baku dan resep", "stok", 1),
    ("ekspor_impor", "Ekspor dan unggah template", "produk", 1),
    ("diskon", "Kelola diskon", "penjualan", 1),
    ("pajak_per_produk", "Pajak per produk", "penjualan", 1),
    ("tipe_order", "Tipe pesanan", "penjualan", 1),
    ("kelola_karyawan", "Kelola karyawan", "pengguna", 1),
    ("poin_loyalitas", "Poin loyalitas pelanggan", "pelanggan", 1),
    ("diskon_member", "Diskon member", "pelanggan", 1),
    ("survei", "Survei pelanggan", "pelanggan", 1),
    ("absensi", "Absensi karyawan", "pengguna", 1),
    ("struk_ringkas", "Struk ringkas", "penjualan", 2),
    ("tiket_dapur", "Cetak tiket dapur", "penjualan", 2),
    ("catatan_struk", "Catatan tambahan di struk", "penjualan", 2),
    ("service_per_tipe_order", "Service fee per tipe pesanan", "penjualan", 2),
    ("status_pesanan", "Status pesanan", "penjualan", 2),
    ("dp_kasbon", "DP untuk kasbon", "penjualan", 2),
    ("nomor_antrean", "Nomor antrean", "penjualan", 2),
    ("label_pembayaran", "Label metode pembayaran", "penjualan", 2),
    ("logo_struk", "Logo usaha di struk", "penjualan", 2),
    ("bundling", "Kelola bundling produk", "produk", 2),
    ("pengingat_kedaluwarsa", "Pengingat kedaluwarsa produk", "stok", 2),
    ("harga_grosir", "Harga grosir", "produk", 2),
    ("expenses", "Catat pengeluaran & biaya operasional", "akuntansi", 1),
]

_PAKET = [("Gratis", 0), ("Pro", 1), ("Bisnis", 2)]

# Batas hari utk fitur laporan_dasar - lihat migrasi 0002
# (batas_laporan_dasar). None = tanpa batas.
_BATAS_LAPORAN_DASAR: dict[str, int | None] = {"Gratis": 30, "Pro": 365, "Bisnis": None}


async def seed_paket_fitur(db: AsyncSession) -> dict[str, Paket]:
    """Return dict nama_paket -> Paket, supaya test lain bisa langsung
    pakai id-nya (mis. bikin Langganan) tanpa query ulang."""

    paket_rows = {nama: Paket(nama=nama, urutan=urutan) for nama, urutan in _PAKET}
    db.add_all(paket_rows.values())
    await db.flush()

    fitur_rows = {kode: Fitur(kode=kode, nama=nama, modul=modul, tingkat=tingkat) for kode, nama, modul, tingkat in _FITUR}
    db.add_all(fitur_rows.values())
    await db.flush()

    for nama_paket, paket in paket_rows.items():
        for kode, fitur in fitur_rows.items():
            if fitur.tingkat <= paket.urutan:
                batas = _BATAS_LAPORAN_DASAR[nama_paket] if kode == "laporan_dasar" else None
                db.add(PaketFitur(paket_id=paket.id, fitur_id=fitur.id, batas=batas))

    await db.commit()
    return paket_rows
