"""Katalog IMOGI: 4 paket (Free, Starter, Professional, Enterprise), 87 fitur, dan kebutuhan
fitur per jenis usaha Makanan & Minuman.

Sumber: `IMOGI POS Menu & Fitur.html` (5 Nov 2026) - dijadikan acuan utama (moment of truth) oleh
pengguna pada 2026-11-08. File ini DIBANGKITKAN dari data berkas itu; jangan disunting tangan.

Keputusan desain:
- Baris paket lama dipakai ulang supaya langganan dan permintaan_upgrade yang sudah ada tetap valid:
  Gratis -> Free, Pro -> Starter, Bisnis -> Enterprise (paket tertinggi), lalu Professional disisipkan
  di antaranya. PEMETAAN INI ASUMSI; sesuaikan bila lead menghendaki lain.
- 32 kode fitur lama dipertahankan (aplikasi dan backend memakainya langsung); kolom baru `kunci_imogi`
  dan `nomor_imogi` memetakannya ke kunci IMOGI sebagai kontrak untuk dashboard. 55 fitur IMOGI lain
  ditambahkan dengan kode = kunci IMOGI (garis bawah). Fitur baru belum memiliki implementasi, jadi
  belum menggerbang apa pun.
- HARGA dan KUOTA di bawah adalah HARGA CONTOH (dokumen IMOGI tidak memuatnya) - lead/admin perlu
  menetapkan lewat konfigurasi paket. Starter 59.000, Professional 99.000, Enterprise 149.000 per
  bulan (tahunan = 10x). Kuota Free: 1 outlet, 2 pengguna, 100 produk (tetap dari katalog lama).
- Batas riwayat laporan (laporan_dasar): Free 30 hari, Starter 365, Professional 365, Enterprise tanpa
  batas. Nilai Professional adalah tebakan.

Revision ID: 0010
Revises: 0009
Create Date: 2026-11-08
"""

from typing import Sequence, Union

from alembic import op

from app.core.ddl_split import split_statements

revision: str = "0010"
down_revision: Union[str, None] = "0009"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_UPGRADE_SQL = """
-- 1. PAKET: Bisnis->Enterprise, Pro->Starter, Gratis->Free, tambah Professional
UPDATE paket SET nama = 'Enterprise', urutan = 3, harga_bulanan = 149000, harga_tahunan = 1490000 WHERE nama = 'Bisnis';
UPDATE paket SET nama = 'Starter' WHERE nama = 'Pro';
UPDATE paket SET nama = 'Free' WHERE nama = 'Gratis';
INSERT INTO paket (nama, urutan, harga_bulanan, harga_tahunan, maks_outlet, maks_pengguna, maks_produk) VALUES ('Professional', 2, 99000, 990000, NULL, NULL, NULL);

-- 2. FITUR: kolom pemetaan ke kunci dan nomor fitur IMOGI
ALTER TABLE fitur ADD COLUMN kunci_imogi varchar(50), ADD COLUMN nomor_imogi int;

-- 3. 87 FITUR IMOGI (32 kode lama dipertahankan agar aplikasi dan backend tidak rusak)
UPDATE fitur SET nama = 'Kasir (POS)', modul = 'Kasir & Transaksi', tingkat = 0, kunci_imogi = 'pos', nomor_imogi = 1 WHERE kode = 'pos';
UPDATE fitur SET nama = 'Scan barcode produk', modul = 'Kasir & Transaksi', tingkat = 1, kunci_imogi = 'barcode', nomor_imogi = 2 WHERE kode = 'scan_barcode';
UPDATE fitur SET nama = 'Kelola diskon', modul = 'Kasir & Transaksi', tingkat = 0, kunci_imogi = 'discount', nomor_imogi = 3 WHERE kode = 'diskon';
UPDATE fitur SET nama = 'Pajak per produk', modul = 'Kasir & Transaksi', tingkat = 1, kunci_imogi = 'product-tax', nomor_imogi = 4 WHERE kode = 'pajak_per_produk';
UPDATE fitur SET nama = 'Tipe pesanan (dine-in/takeaway/delivery)', modul = 'Kasir & Transaksi', tingkat = 1, kunci_imogi = 'order-types', nomor_imogi = 5 WHERE kode = 'tipe_order';
UPDATE fitur SET nama = 'Biaya layanan per tipe pesanan', modul = 'Kasir & Transaksi', tingkat = 3, kunci_imogi = 'service-charge', nomor_imogi = 6 WHERE kode = 'service_per_tipe_order';
INSERT INTO fitur (kode, nama, modul, tingkat, kunci_imogi, nomor_imogi) VALUES ('hold', 'Simpan pesanan (hold / open bill)', 'Kasir & Transaksi', 0, 'hold', 7);
INSERT INTO fitur (kode, nama, modul, tingkat, kunci_imogi, nomor_imogi) VALUES ('vehicle_buyer', 'Data pembeli & nama STNK/BPKB', 'Kasir & Transaksi', 0, 'vehicle-buyer', 8);
INSERT INTO fitur (kode, nama, modul, tingkat, kunci_imogi, nomor_imogi) VALUES ('trade_in', 'Tukar tambah (trade-in) kendaraan', 'Kasir & Transaksi', 2, 'trade-in', 9);
UPDATE fitur SET nama = 'Pembayaran QRIS', modul = 'Pembayaran', tingkat = 1, kunci_imogi = 'qris', nomor_imogi = 10 WHERE kode = 'qris';
INSERT INTO fitur (kode, nama, modul, tingkat, kunci_imogi, nomor_imogi) VALUES ('leasing', 'Pembayaran via leasing (DP + pencairan leasing)', 'Pembayaran', 1, 'leasing', 11);
INSERT INTO fitur (kode, nama, modul, tingkat, kunci_imogi, nomor_imogi) VALUES ('invoice', 'Invoice tagihan pelanggan (A4, jatuh tempo)', 'Pembayaran', 1, 'invoice', 12);
INSERT INTO fitur (kode, nama, modul, tingkat, kunci_imogi, nomor_imogi) VALUES ('card', 'Pembayaran kartu debit/kredit (EDC)', 'Pembayaran', 0, 'card', 13);
INSERT INTO fitur (kode, nama, modul, tingkat, kunci_imogi, nomor_imogi) VALUES ('transfer', 'Pembayaran transfer bank', 'Pembayaran', 0, 'transfer', 14);
INSERT INTO fitur (kode, nama, modul, tingkat, kunci_imogi, nomor_imogi) VALUES ('split_payment', 'Split payment (bayar campur)', 'Pembayaran', 1, 'split-payment', 15);
UPDATE fitur SET nama = 'Pembayaran hutang (bon)', modul = 'Pembayaran', tingkat = 1, kunci_imogi = 'credit', nomor_imogi = 16 WHERE kode = 'kasbon';
UPDATE fitur SET nama = 'DP untuk hutang', modul = 'Pembayaran', tingkat = 3, kunci_imogi = 'deposit', nomor_imogi = 17 WHERE kode = 'dp_kasbon';
UPDATE fitur SET nama = 'Label jenis pembayaran', modul = 'Pembayaran', tingkat = 3, kunci_imogi = 'payment-label', nomor_imogi = 18 WHERE kode = 'label_pembayaran';
INSERT INTO fitur (kode, nama, modul, tingkat, kunci_imogi, nomor_imogi) VALUES ('dues', 'Iuran rutin & status bayar anggota', 'Pembayaran', 0, 'dues', 19);
INSERT INTO fitur (kode, nama, modul, tingkat, kunci_imogi, nomor_imogi) VALUES ('dues_reminder', 'Pengingat iuran via WhatsApp', 'Pembayaran', 1, 'dues-reminder', 20);
INSERT INTO fitur (kode, nama, modul, tingkat, kunci_imogi, nomor_imogi) VALUES ('arisan', 'Kelompok arisan & kocokan oleh admin', 'Pembayaran', 0, 'arisan', 21);
UPDATE fitur SET nama = 'Cetak struk', modul = 'Struk & Cetak', tingkat = 0, kunci_imogi = 'receipt', nomor_imogi = 22 WHERE kode = 'cetak_struk';
UPDATE fitur SET nama = 'Struk ringkas', modul = 'Struk & Cetak', tingkat = 3, kunci_imogi = 'receipt-compact', nomor_imogi = 23 WHERE kode = 'struk_ringkas';
UPDATE fitur SET nama = 'Logo usaha di struk', modul = 'Struk & Cetak', tingkat = 3, kunci_imogi = 'receipt-logo', nomor_imogi = 24 WHERE kode = 'logo_struk';
UPDATE fitur SET nama = 'Catatan tambahan di struk', modul = 'Struk & Cetak', tingkat = 3, kunci_imogi = 'receipt-note', nomor_imogi = 25 WHERE kode = 'catatan_struk';
UPDATE fitur SET nama = 'Status pesanan', modul = 'Pesanan & Dapur', tingkat = 3, kunci_imogi = 'order-status', nomor_imogi = 26 WHERE kode = 'status_pesanan';
INSERT INTO fitur (kode, nama, modul, tingkat, kunci_imogi, nomor_imogi) VALUES ('pay_later', 'Terima order, bayar belakangan (nota order)', 'Pesanan & Dapur', 0, 'pay-later', 27);
INSERT INTO fitur (kode, nama, modul, tingkat, kunci_imogi, nomor_imogi) VALUES ('towing_order', 'Order towing (multi rute & kendaraan, dokumen per kendaraan)', 'Pesanan & Dapur', 0, 'towing-order', 28);
INSERT INTO fitur (kode, nama, modul, tingkat, kunci_imogi, nomor_imogi) VALUES ('towing_subcon', 'Subkon towing ke vendor (1 dokumen per order)', 'Pesanan & Dapur', 1, 'towing-subcon', 29);
INSERT INTO fitur (kode, nama, modul, tingkat, kunci_imogi, nomor_imogi) VALUES ('vehicle_docs', 'Proses dokumen STNK/BPKB & balik nama', 'Pesanan & Dapur', 1, 'vehicle-docs', 30);
INSERT INTO fitur (kode, nama, modul, tingkat, kunci_imogi, nomor_imogi) VALUES ('queue_lanes', 'Antrian multi loket / ruang', 'Pesanan & Dapur', 3, 'queue-lanes', 31);
INSERT INTO fitur (kode, nama, modul, tingkat, kunci_imogi, nomor_imogi) VALUES ('queue_staff', 'Pilih petugas saat ambil antrian', 'Pesanan & Dapur', 1, 'queue-staff', 32);
INSERT INTO fitur (kode, nama, modul, tingkat, kunci_imogi, nomor_imogi) VALUES ('vehicle_intake', 'Cek kendaraan masuk & riwayat servis per plat', 'Pesanan & Dapur', 1, 'vehicle-intake', 33);
UPDATE fitur SET nama = 'Nomor antrian', modul = 'Pesanan & Dapur', tingkat = 3, kunci_imogi = 'queue-number', nomor_imogi = 34 WHERE kode = 'nomor_antrean';
UPDATE fitur SET nama = 'Cetak tiket pesanan dapur', modul = 'Pesanan & Dapur', tingkat = 3, kunci_imogi = 'kitchen-ticket', nomor_imogi = 35 WHERE kode = 'tiket_dapur';
INSERT INTO fitur (kode, nama, modul, tingkat, kunci_imogi, nomor_imogi) VALUES ('catalog', 'Kelola produk, kategori & harga', 'Katalog Produk & Harga', 0, 'catalog', 36);
INSERT INTO fitur (kode, nama, modul, tingkat, kunci_imogi, nomor_imogi) VALUES ('product_cost', 'Harga beli & margin produk', 'Katalog Produk & Harga', 0, 'product-cost', 37);
UPDATE fitur SET nama = 'Upload produk via template', modul = 'Katalog Produk & Harga', tingkat = 1, kunci_imogi = 'catalog-import', nomor_imogi = 38 WHERE kode = 'ekspor_impor';
INSERT INTO fitur (kode, nama, modul, tingkat, kunci_imogi, nomor_imogi) VALUES ('catalog_export', 'Ekspor produk', 'Katalog Produk & Harga', 1, 'catalog-export', 39);
UPDATE fitur SET nama = 'Kelola paket (bundle)', modul = 'Katalog Produk & Harga', tingkat = 3, kunci_imogi = 'bundle', nomor_imogi = 40 WHERE kode = 'bundling';
UPDATE fitur SET nama = 'Kelola harga grosir', modul = 'Katalog Produk & Harga', tingkat = 3, kunci_imogi = 'wholesale', nomor_imogi = 41 WHERE kode = 'harga_grosir';
INSERT INTO fitur (kode, nama, modul, tingkat, kunci_imogi, nomor_imogi) VALUES ('product_options', 'Varian & tambahan produk (ukuran, level, topping)', 'Katalog Produk & Harga', 1, 'product-options', 42);
INSERT INTO fitur (kode, nama, modul, tingkat, kunci_imogi, nomor_imogi) VALUES ('pack_units', 'Jual per kemasan (pcs, dus, pak)', 'Katalog Produk & Harga', 1, 'pack-units', 43);
INSERT INTO fitur (kode, nama, modul, tingkat, kunci_imogi, nomor_imogi) VALUES ('drug_class', 'Golongan obat & peringatan resep', 'Katalog Produk & Harga', 0, 'drug-class', 44);
INSERT INTO fitur (kode, nama, modul, tingkat, kunci_imogi, nomor_imogi) VALUES ('service_duration', 'Durasi layanan', 'Katalog Produk & Harga', 0, 'service-duration', 45);
INSERT INTO fitur (kode, nama, modul, tingkat, kunci_imogi, nomor_imogi) VALUES ('service_turnaround', 'Estimasi selesai per layanan', 'Katalog Produk & Harga', 1, 'service-turnaround', 46);
INSERT INTO fitur (kode, nama, modul, tingkat, kunci_imogi, nomor_imogi) VALUES ('vehicle_units', 'Data unit kendaraan (no. rangka, no. mesin, spesifikasi)', 'Katalog Produk & Harga', 0, 'vehicle-units', 47);
INSERT INTO fitur (kode, nama, modul, tingkat, kunci_imogi, nomor_imogi) VALUES ('vehicle_inspection', 'Inspeksi & kondisi unit bekas', 'Katalog Produk & Harga', 2, 'vehicle-inspection', 48);
UPDATE fitur SET nama = 'Kelola stok produk', modul = 'Stok & Resep', tingkat = 0, kunci_imogi = 'stock', nomor_imogi = 49 WHERE kode = 'kelola_stok';
UPDATE fitur SET nama = 'Pengingat kedaluwarsa produk', modul = 'Stok & Resep', tingkat = 3, kunci_imogi = 'stock-expiry', nomor_imogi = 50 WHERE kode = 'pengingat_kedaluwarsa';
UPDATE fitur SET nama = 'Bahan baku & resep produk', modul = 'Stok & Resep', tingkat = 2, kunci_imogi = 'recipe', nomor_imogi = 51 WHERE kode = 'resep';
UPDATE fitur SET nama = 'Kelola pelanggan', modul = 'Pelanggan & Loyalti', tingkat = 1, kunci_imogi = 'customers', nomor_imogi = 52 WHERE kode = 'kelola_pelanggan';
INSERT INTO fitur (kode, nama, modul, tingkat, kunci_imogi, nomor_imogi) VALUES ('customer_import', 'Upload pelanggan via template', 'Pelanggan & Loyalti', 2, 'customer-import', 53);
UPDATE fitur SET nama = 'Poin loyalti pelanggan', modul = 'Pelanggan & Loyalti', tingkat = 2, kunci_imogi = 'loyalty-points', nomor_imogi = 54 WHERE kode = 'poin_loyalitas';
UPDATE fitur SET nama = 'Diskon member', modul = 'Pelanggan & Loyalti', tingkat = 2, kunci_imogi = 'member-discount', nomor_imogi = 55 WHERE kode = 'diskon_member';
INSERT INTO fitur (kode, nama, modul, tingkat, kunci_imogi, nomor_imogi) VALUES ('birthday_promo', 'Promo ulang tahun pelanggan', 'Pelanggan & Loyalti', 2, 'birthday-promo', 56);
INSERT INTO fitur (kode, nama, modul, tingkat, kunci_imogi, nomor_imogi) VALUES ('customer_broadcast', 'Kirim WA ke banyak pelanggan', 'Pelanggan & Loyalti', 2, 'customer-broadcast', 57);
INSERT INTO fitur (kode, nama, modul, tingkat, kunci_imogi, nomor_imogi) VALUES ('service_reminder', 'Pengingat servis / kontrol berkala', 'Pelanggan & Loyalti', 2, 'service-reminder', 58);
UPDATE fitur SET nama = 'Survei pelanggan', modul = 'Pelanggan & Loyalti', tingkat = 2, kunci_imogi = 'customer-survey', nomor_imogi = 59 WHERE kode = 'survei';
INSERT INTO fitur (kode, nama, modul, tingkat, kunci_imogi, nomor_imogi) VALUES ('members', 'Data anggota (kelas / kelompok)', 'Pelanggan & Loyalti', 0, 'members', 60);
UPDATE fitur SET nama = 'Kelola karyawan', modul = 'Karyawan', tingkat = 1, kunci_imogi = 'employees', nomor_imogi = 61 WHERE kode = 'kelola_karyawan';
UPDATE fitur SET nama = 'Absensi karyawan', modul = 'Karyawan', tingkat = 2, kunci_imogi = 'attendance', nomor_imogi = 62 WHERE kode = 'absensi';
INSERT INTO fitur (kode, nama, modul, tingkat, kunci_imogi, nomor_imogi) VALUES ('staff_schedule', 'Jadwal shift mingguan & cuti', 'Karyawan', 2, 'staff-schedule', 63);
UPDATE fitur SET nama = 'Laporan Penjualan (sesuai periode langganan)', modul = 'Laporan & Analitik', tingkat = 0, kunci_imogi = 'sales-report', nomor_imogi = 64 WHERE kode = 'laporan_dasar';
UPDATE fitur SET nama = 'Tren penjualan', modul = 'Laporan & Analitik', tingkat = 1, kunci_imogi = 'sales-trend', nomor_imogi = 65 WHERE kode = 'tren_penjualan';
INSERT INTO fitur (kode, nama, modul, tingkat, kunci_imogi, nomor_imogi) VALUES ('trip_allowance', 'Uang jalan driver otomatis per rute', 'Akuntansi', 1, 'trip-allowance', 66);
INSERT INTO fitur (kode, nama, modul, tingkat, kunci_imogi, nomor_imogi) VALUES ('expenses', 'Catat pengeluaran & biaya operasional', 'Akuntansi', 1, 'expenses', 67);
INSERT INTO fitur (kode, nama, modul, tingkat, kunci_imogi, nomor_imogi) VALUES ('cash_shift', 'Buka/tutup shift & rekonsiliasi kas', 'Akuntansi', 1, 'cash-shift', 68);
INSERT INTO fitur (kode, nama, modul, tingkat, kunci_imogi, nomor_imogi) VALUES ('profit_loss', 'Laporan laba rugi', 'Akuntansi', 2, 'profit-loss', 69);
INSERT INTO fitur (kode, nama, modul, tingkat, kunci_imogi, nomor_imogi) VALUES ('tax_pph', 'Rekap pajak PPh Final UMKM (0,5%)', 'Akuntansi', 2, 'tax-pph', 70);
INSERT INTO fitur (kode, nama, modul, tingkat, kunci_imogi, nomor_imogi) VALUES ('payables', 'Piutang & hutang usaha (AR/AP)', 'Akuntansi', 2, 'payables', 71);
INSERT INTO fitur (kode, nama, modul, tingkat, kunci_imogi, nomor_imogi) VALUES ('product_margin', 'HPP & margin per produk/layanan', 'Akuntansi', 2, 'product-margin', 72);
INSERT INTO fitur (kode, nama, modul, tingkat, kunci_imogi, nomor_imogi) VALUES ('tax_recap', 'Rekap pajak PPN & PB1', 'Akuntansi', 2, 'tax-recap', 73);
INSERT INTO fitur (kode, nama, modul, tingkat, kunci_imogi, nomor_imogi) VALUES ('settlement', 'Settlement & rekonsiliasi QRIS/e-wallet', 'Akuntansi', 2, 'settlement', 74);
INSERT INTO fitur (kode, nama, modul, tingkat, kunci_imogi, nomor_imogi) VALUES ('commission', 'Komisi & bagi hasil karyawan', 'Akuntansi', 2, 'commission', 75);
INSERT INTO fitur (kode, nama, modul, tingkat, kunci_imogi, nomor_imogi) VALUES ('payroll', 'Penggajian (payroll) & kasbon karyawan', 'Akuntansi', 3, 'payroll', 76);
INSERT INTO fitur (kode, nama, modul, tingkat, kunci_imogi, nomor_imogi) VALUES ('payroll_tax', 'BPJS & PPh 21 di penggajian', 'Akuntansi', 3, 'payroll-tax', 77);
INSERT INTO fitur (kode, nama, modul, tingkat, kunci_imogi, nomor_imogi) VALUES ('year_end_closing', 'Tutup buku akhir tahun', 'Akuntansi', 3, 'year-end-closing', 78);
INSERT INTO fitur (kode, nama, modul, tingkat, kunci_imogi, nomor_imogi) VALUES ('prepaid_revenue', 'Pendapatan diterima di muka (deposit/membership)', 'Akuntansi', 3, 'prepaid-revenue', 79);
INSERT INTO fitur (kode, nama, modul, tingkat, kunci_imogi, nomor_imogi) VALUES ('journal', 'Chart of Accounts & jurnal umum', 'Akuntansi', 3, 'journal', 80);
INSERT INTO fitur (kode, nama, modul, tingkat, kunci_imogi, nomor_imogi) VALUES ('ledger', 'Buku besar, neraca & arus kas', 'Akuntansi', 3, 'ledger', 81);
INSERT INTO fitur (kode, nama, modul, tingkat, kunci_imogi, nomor_imogi) VALUES ('budget', 'Anggaran & proyeksi arus kas', 'Akuntansi', 3, 'budget', 82);
INSERT INTO fitur (kode, nama, modul, tingkat, kunci_imogi, nomor_imogi) VALUES ('fixed_assets', 'Aset tetap & penyusutan', 'Akuntansi', 3, 'fixed-assets', 83);
INSERT INTO fitur (kode, nama, modul, tingkat, kunci_imogi, nomor_imogi) VALUES ('consolidation', 'Laporan keuangan konsolidasi multi-outlet', 'Akuntansi', 3, 'consolidation', 84);
INSERT INTO fitur (kode, nama, modul, tingkat, kunci_imogi, nomor_imogi) VALUES ('accounting_export', 'Ekspor ke software akuntansi (Jurnal, Accurate, Zahir)', 'Akuntansi', 3, 'accounting-export', 85);
INSERT INTO fitur (kode, nama, modul, tingkat, kunci_imogi, nomor_imogi) VALUES ('events', 'Kegiatan, kas & LPJ', 'Akuntansi', 0, 'events', 86);
UPDATE fitur SET nama = 'Multi-Outlet', modul = 'Multi-Outlet', tingkat = 2, kunci_imogi = 'multi-outlet', nomor_imogi = 87 WHERE kode = 'multi_outlet';
CREATE UNIQUE INDEX ux_fitur_kunci_imogi ON fitur (kunci_imogi) WHERE kunci_imogi IS NOT NULL;

-- 4. PAKET_FITUR: paket membuka semua fitur dengan tingkat <= urutan paketnya
DELETE FROM paket_fitur;
INSERT INTO paket_fitur (paket_id, fitur_id) SELECT p.id, f.id FROM paket p JOIN fitur f ON f.tingkat <= p.urutan;
UPDATE paket_fitur pf SET batas = CASE p.nama WHEN 'Free' THEN 30 WHEN 'Starter' THEN 365 WHEN 'Professional' THEN 365 ELSE NULL END FROM paket p, fitur f WHERE pf.paket_id = p.id AND pf.fitur_id = f.id AND f.kode = 'laporan_dasar';

-- 5. KEBUTUHAN FITUR per jenis usaha Makanan & Minuman (inti / opsional / na) dari dokumen IMOGI
CREATE TABLE fitur_kebutuhan (
  fitur_id     uuid NOT NULL REFERENCES fitur(id),
  jenis_usaha  varchar(3) NOT NULL,
  kebutuhan    varchar(8) NOT NULL CHECK (kebutuhan IN ('inti','opsional','na')),
  PRIMARY KEY (fitur_id, jenis_usaha)
);
INSERT INTO fitur_kebutuhan (fitur_id, jenis_usaha, kebutuhan) SELECT id, 'CAF', 'inti' FROM fitur WHERE kunci_imogi IN ('pos', 'discount', 'product-tax', 'order-types', 'service-charge', 'hold', 'qris', 'card', 'split-payment', 'payment-label', 'receipt', 'receipt-compact', 'receipt-logo', 'order-status', 'queue-number', 'kitchen-ticket', 'catalog', 'product-cost', 'catalog-import', 'bundle', 'product-options', 'recipe', 'loyalty-points', 'member-discount', 'birthday-promo', 'customer-survey', 'employees', 'attendance', 'staff-schedule', 'sales-report', 'sales-trend', 'expenses', 'cash-shift', 'profit-loss', 'tax-pph', 'product-margin', 'tax-recap', 'settlement', 'payroll', 'journal', 'ledger', 'budget', 'fixed-assets', 'consolidation', 'accounting-export', 'multi-outlet');
INSERT INTO fitur_kebutuhan (fitur_id, jenis_usaha, kebutuhan) SELECT id, 'CAF', 'opsional' FROM fitur WHERE kunci_imogi IN ('barcode', 'transfer', 'credit', 'receipt-note', 'pay-later', 'catalog-export', 'stock', 'stock-expiry', 'customers', 'customer-import', 'customer-broadcast', 'payables', 'payroll-tax', 'year-end-closing', 'prepaid-revenue');
INSERT INTO fitur_kebutuhan (fitur_id, jenis_usaha, kebutuhan) SELECT id, 'CAF', 'na' FROM fitur WHERE kunci_imogi IN ('vehicle-buyer', 'trade-in', 'leasing', 'invoice', 'deposit', 'dues', 'dues-reminder', 'arisan', 'towing-order', 'towing-subcon', 'vehicle-docs', 'queue-lanes', 'queue-staff', 'vehicle-intake', 'wholesale', 'pack-units', 'drug-class', 'service-duration', 'service-turnaround', 'vehicle-units', 'vehicle-inspection', 'service-reminder', 'members', 'trip-allowance', 'commission', 'events');
INSERT INTO fitur_kebutuhan (fitur_id, jenis_usaha, kebutuhan) SELECT id, 'RES', 'inti' FROM fitur WHERE kunci_imogi IN ('pos', 'discount', 'product-tax', 'order-types', 'service-charge', 'hold', 'qris', 'card', 'split-payment', 'payment-label', 'receipt', 'receipt-logo', 'order-status', 'kitchen-ticket', 'catalog', 'product-cost', 'catalog-import', 'bundle', 'product-options', 'recipe', 'customer-survey', 'employees', 'attendance', 'staff-schedule', 'sales-report', 'sales-trend', 'expenses', 'cash-shift', 'profit-loss', 'tax-pph', 'product-margin', 'tax-recap', 'settlement', 'payroll', 'journal', 'ledger', 'budget', 'fixed-assets', 'accounting-export');
INSERT INTO fitur_kebutuhan (fitur_id, jenis_usaha, kebutuhan) SELECT id, 'RES', 'opsional' FROM fitur WHERE kunci_imogi IN ('transfer', 'credit', 'receipt-compact', 'receipt-note', 'pay-later', 'catalog-export', 'stock', 'stock-expiry', 'customers', 'customer-import', 'loyalty-points', 'member-discount', 'birthday-promo', 'customer-broadcast', 'payables', 'payroll-tax', 'year-end-closing', 'prepaid-revenue', 'consolidation', 'multi-outlet');
INSERT INTO fitur_kebutuhan (fitur_id, jenis_usaha, kebutuhan) SELECT id, 'RES', 'na' FROM fitur WHERE kunci_imogi IN ('barcode', 'vehicle-buyer', 'trade-in', 'leasing', 'invoice', 'deposit', 'dues', 'dues-reminder', 'arisan', 'towing-order', 'towing-subcon', 'vehicle-docs', 'queue-lanes', 'queue-staff', 'vehicle-intake', 'queue-number', 'wholesale', 'pack-units', 'drug-class', 'service-duration', 'service-turnaround', 'vehicle-units', 'vehicle-inspection', 'service-reminder', 'members', 'trip-allowance', 'commission', 'events');
INSERT INTO fitur_kebutuhan (fitur_id, jenis_usaha, kebutuhan) SELECT id, 'CAT', 'inti' FROM fitur WHERE kunci_imogi IN ('pos', 'discount', 'order-types', 'hold', 'qris', 'card', 'transfer', 'credit', 'deposit', 'receipt', 'order-status', 'catalog', 'product-cost', 'catalog-import', 'bundle', 'recipe', 'customers', 'employees', 'attendance', 'staff-schedule', 'sales-report', 'sales-trend', 'expenses', 'cash-shift', 'profit-loss', 'tax-pph', 'payables', 'product-margin', 'payroll', 'prepaid-revenue', 'journal', 'ledger', 'budget', 'accounting-export');
INSERT INTO fitur_kebutuhan (fitur_id, jenis_usaha, kebutuhan) SELECT id, 'CAT', 'opsional' FROM fitur WHERE kunci_imogi IN ('product-tax', 'service-charge', 'split-payment', 'payment-label', 'receipt-logo', 'receipt-note', 'pay-later', 'kitchen-ticket', 'catalog-export', 'wholesale', 'product-options', 'stock', 'stock-expiry', 'customer-import', 'birthday-promo', 'customer-broadcast', 'customer-survey', 'tax-recap', 'settlement', 'payroll-tax', 'year-end-closing', 'fixed-assets', 'consolidation', 'multi-outlet');
INSERT INTO fitur_kebutuhan (fitur_id, jenis_usaha, kebutuhan) SELECT id, 'CAT', 'na' FROM fitur WHERE kunci_imogi IN ('barcode', 'vehicle-buyer', 'trade-in', 'leasing', 'invoice', 'dues', 'dues-reminder', 'arisan', 'receipt-compact', 'towing-order', 'towing-subcon', 'vehicle-docs', 'queue-lanes', 'queue-staff', 'vehicle-intake', 'queue-number', 'pack-units', 'drug-class', 'service-duration', 'service-turnaround', 'vehicle-units', 'vehicle-inspection', 'loyalty-points', 'member-discount', 'service-reminder', 'members', 'trip-allowance', 'commission', 'events');
INSERT INTO fitur_kebutuhan (fitur_id, jenis_usaha, kebutuhan) SELECT id, 'BRD', 'inti' FROM fitur WHERE kunci_imogi IN ('pos', 'discount', 'order-types', 'hold', 'qris', 'card', 'receipt', 'receipt-compact', 'catalog', 'product-cost', 'catalog-import', 'stock', 'stock-expiry', 'recipe', 'loyalty-points', 'employees', 'sales-report', 'sales-trend', 'expenses', 'cash-shift', 'profit-loss', 'tax-pph', 'payables', 'product-margin', 'settlement');
INSERT INTO fitur_kebutuhan (fitur_id, jenis_usaha, kebutuhan) SELECT id, 'BRD', 'opsional' FROM fitur WHERE kunci_imogi IN ('barcode', 'product-tax', 'transfer', 'split-payment', 'credit', 'deposit', 'payment-label', 'receipt-logo', 'receipt-note', 'order-status', 'queue-number', 'kitchen-ticket', 'catalog-export', 'bundle', 'wholesale', 'product-options', 'customers', 'customer-import', 'member-discount', 'birthday-promo', 'customer-broadcast', 'customer-survey', 'attendance', 'staff-schedule', 'tax-recap', 'payroll', 'payroll-tax', 'year-end-closing', 'prepaid-revenue', 'journal', 'ledger', 'budget', 'fixed-assets', 'consolidation', 'accounting-export', 'multi-outlet');
INSERT INTO fitur_kebutuhan (fitur_id, jenis_usaha, kebutuhan) SELECT id, 'BRD', 'na' FROM fitur WHERE kunci_imogi IN ('service-charge', 'vehicle-buyer', 'trade-in', 'leasing', 'invoice', 'dues', 'dues-reminder', 'arisan', 'pay-later', 'towing-order', 'towing-subcon', 'vehicle-docs', 'queue-lanes', 'queue-staff', 'vehicle-intake', 'pack-units', 'drug-class', 'service-duration', 'service-turnaround', 'vehicle-units', 'vehicle-inspection', 'service-reminder', 'members', 'trip-allowance', 'commission', 'events');
INSERT INTO fitur_kebutuhan (fitur_id, jenis_usaha, kebutuhan) SELECT id, 'FRZ', 'inti' FROM fitur WHERE kunci_imogi IN ('pos', 'barcode', 'discount', 'hold', 'qris', 'card', 'credit', 'receipt', 'catalog', 'product-cost', 'catalog-import', 'catalog-export', 'wholesale', 'pack-units', 'stock', 'stock-expiry', 'employees', 'sales-report', 'sales-trend', 'expenses', 'cash-shift', 'profit-loss', 'tax-pph', 'payables', 'product-margin', 'settlement');
INSERT INTO fitur_kebutuhan (fitur_id, jenis_usaha, kebutuhan) SELECT id, 'FRZ', 'opsional' FROM fitur WHERE kunci_imogi IN ('product-tax', 'order-types', 'transfer', 'split-payment', 'payment-label', 'receipt-compact', 'receipt-logo', 'receipt-note', 'bundle', 'recipe', 'customers', 'customer-import', 'loyalty-points', 'customer-survey', 'attendance', 'staff-schedule', 'tax-recap', 'payroll', 'payroll-tax', 'year-end-closing', 'journal', 'ledger', 'budget', 'fixed-assets', 'consolidation', 'accounting-export', 'multi-outlet');
INSERT INTO fitur_kebutuhan (fitur_id, jenis_usaha, kebutuhan) SELECT id, 'FRZ', 'na' FROM fitur WHERE kunci_imogi IN ('service-charge', 'vehicle-buyer', 'trade-in', 'leasing', 'invoice', 'deposit', 'dues', 'dues-reminder', 'arisan', 'order-status', 'pay-later', 'towing-order', 'towing-subcon', 'vehicle-docs', 'queue-lanes', 'queue-staff', 'vehicle-intake', 'queue-number', 'kitchen-ticket', 'product-options', 'drug-class', 'service-duration', 'service-turnaround', 'vehicle-units', 'vehicle-inspection', 'member-discount', 'birthday-promo', 'customer-broadcast', 'service-reminder', 'members', 'trip-allowance', 'commission', 'prepaid-revenue', 'events');
INSERT INTO fitur_kebutuhan (fitur_id, jenis_usaha, kebutuhan) SELECT id, 'BEV', 'inti' FROM fitur WHERE kunci_imogi IN ('pos', 'discount', 'order-types', 'hold', 'qris', 'split-payment', 'receipt', 'receipt-compact', 'queue-number', 'kitchen-ticket', 'catalog', 'product-cost', 'catalog-import', 'product-options', 'stock', 'recipe', 'loyalty-points', 'employees', 'sales-report', 'sales-trend', 'expenses', 'cash-shift', 'profit-loss', 'tax-pph', 'payables', 'product-margin', 'settlement', 'consolidation', 'multi-outlet');
INSERT INTO fitur_kebutuhan (fitur_id, jenis_usaha, kebutuhan) SELECT id, 'BEV', 'opsional' FROM fitur WHERE kunci_imogi IN ('barcode', 'product-tax', 'service-charge', 'card', 'transfer', 'credit', 'payment-label', 'receipt-logo', 'receipt-note', 'order-status', 'catalog-export', 'bundle', 'wholesale', 'pack-units', 'stock-expiry', 'customers', 'customer-import', 'member-discount', 'birthday-promo', 'customer-broadcast', 'customer-survey', 'attendance', 'staff-schedule', 'tax-recap', 'payroll', 'payroll-tax', 'year-end-closing', 'journal', 'ledger', 'budget', 'fixed-assets', 'accounting-export');
INSERT INTO fitur_kebutuhan (fitur_id, jenis_usaha, kebutuhan) SELECT id, 'BEV', 'na' FROM fitur WHERE kunci_imogi IN ('vehicle-buyer', 'trade-in', 'leasing', 'invoice', 'deposit', 'dues', 'dues-reminder', 'arisan', 'pay-later', 'towing-order', 'towing-subcon', 'vehicle-docs', 'queue-lanes', 'queue-staff', 'vehicle-intake', 'drug-class', 'service-duration', 'service-turnaround', 'vehicle-units', 'vehicle-inspection', 'service-reminder', 'members', 'trip-allowance', 'commission', 'prepaid-revenue', 'events');
INSERT INTO fitur_kebutuhan (fitur_id, jenis_usaha, kebutuhan) SELECT id, 'STL', 'inti' FROM fitur WHERE kunci_imogi IN ('pos', 'discount', 'order-types', 'hold', 'qris', 'split-payment', 'credit', 'payment-label', 'receipt', 'receipt-compact', 'queue-number', 'kitchen-ticket', 'catalog', 'product-cost', 'catalog-import', 'product-options', 'recipe', 'sales-report', 'sales-trend', 'expenses', 'cash-shift', 'profit-loss', 'tax-pph', 'payables', 'product-margin', 'settlement');
INSERT INTO fitur_kebutuhan (fitur_id, jenis_usaha, kebutuhan) SELECT id, 'STL', 'opsional' FROM fitur WHERE kunci_imogi IN ('product-tax', 'service-charge', 'card', 'transfer', 'receipt-logo', 'receipt-note', 'order-status', 'catalog-export', 'bundle', 'stock', 'stock-expiry', 'customers', 'loyalty-points', 'birthday-promo', 'customer-survey', 'employees', 'attendance', 'staff-schedule', 'tax-recap', 'payroll', 'payroll-tax', 'year-end-closing', 'journal', 'ledger', 'consolidation', 'accounting-export', 'multi-outlet');
INSERT INTO fitur_kebutuhan (fitur_id, jenis_usaha, kebutuhan) SELECT id, 'STL', 'na' FROM fitur WHERE kunci_imogi IN ('barcode', 'vehicle-buyer', 'trade-in', 'leasing', 'invoice', 'deposit', 'dues', 'dues-reminder', 'arisan', 'pay-later', 'towing-order', 'towing-subcon', 'vehicle-docs', 'queue-lanes', 'queue-staff', 'vehicle-intake', 'wholesale', 'pack-units', 'drug-class', 'service-duration', 'service-turnaround', 'vehicle-units', 'vehicle-inspection', 'customer-import', 'member-discount', 'customer-broadcast', 'service-reminder', 'members', 'trip-allowance', 'commission', 'prepaid-revenue', 'budget', 'fixed-assets', 'events');

-- 6. JENIS USAHA: 'fnb' lama -> Kafe & Kedai Kopi (kode IMOGI CAF)
UPDATE toko SET jenis_usaha = 'CAF' WHERE jenis_usaha = 'fnb';
"""

_DOWNGRADE_SQL = """
DROP TABLE IF EXISTS fitur_kebutuhan;
DELETE FROM paket_fitur;
DELETE FROM fitur WHERE nomor_imogi IS NOT NULL AND kode NOT IN ('pos', 'cetak_struk', 'scan_barcode', 'kelola_stok', 'kelola_pelanggan', 'laporan_dasar', 'qris', 'kasbon', 'tren_penjualan', 'multi_outlet', 'resep', 'ekspor_impor', 'diskon', 'pajak_per_produk', 'tipe_order', 'kelola_karyawan', 'poin_loyalitas', 'diskon_member', 'survei', 'absensi', 'struk_ringkas', 'tiket_dapur', 'catatan_struk', 'service_per_tipe_order', 'status_pesanan', 'dp_kasbon', 'nomor_antrean', 'label_pembayaran', 'logo_struk', 'bundling', 'pengingat_kedaluwarsa', 'harga_grosir');
UPDATE fitur SET nama = 'Kasir (POS)', modul = 'penjualan', tingkat = 0 WHERE kode = 'pos';
UPDATE fitur SET nama = 'Cetak struk', modul = 'penjualan', tingkat = 0 WHERE kode = 'cetak_struk';
UPDATE fitur SET nama = 'Scan produk', modul = 'produk', tingkat = 0 WHERE kode = 'scan_barcode';
UPDATE fitur SET nama = 'Kelola stok produk', modul = 'stok', tingkat = 0 WHERE kode = 'kelola_stok';
UPDATE fitur SET nama = 'Kelola pelanggan', modul = 'pelanggan', tingkat = 0 WHERE kode = 'kelola_pelanggan';
UPDATE fitur SET nama = 'Laporan penjualan', modul = 'laporan', tingkat = 0 WHERE kode = 'laporan_dasar';
UPDATE fitur SET nama = 'Pembayaran QRIS', modul = 'penjualan', tingkat = 1 WHERE kode = 'qris';
UPDATE fitur SET nama = 'Bayar dengan utang (kasbon)', modul = 'penjualan', tingkat = 1 WHERE kode = 'kasbon';
UPDATE fitur SET nama = 'Tren penjualan', modul = 'laporan', tingkat = 1 WHERE kode = 'tren_penjualan';
UPDATE fitur SET nama = 'Multi-outlet (biaya per outlet)', modul = 'bisnis', tingkat = 1 WHERE kode = 'multi_outlet';
UPDATE fitur SET nama = 'Bahan baku dan resep', modul = 'stok', tingkat = 1 WHERE kode = 'resep';
UPDATE fitur SET nama = 'Ekspor dan unggah template', modul = 'produk', tingkat = 1 WHERE kode = 'ekspor_impor';
UPDATE fitur SET nama = 'Kelola diskon', modul = 'penjualan', tingkat = 1 WHERE kode = 'diskon';
UPDATE fitur SET nama = 'Pajak per produk', modul = 'penjualan', tingkat = 1 WHERE kode = 'pajak_per_produk';
UPDATE fitur SET nama = 'Tipe pesanan', modul = 'penjualan', tingkat = 1 WHERE kode = 'tipe_order';
UPDATE fitur SET nama = 'Kelola karyawan', modul = 'pengguna', tingkat = 1 WHERE kode = 'kelola_karyawan';
UPDATE fitur SET nama = 'Poin loyalitas pelanggan', modul = 'pelanggan', tingkat = 1 WHERE kode = 'poin_loyalitas';
UPDATE fitur SET nama = 'Diskon member', modul = 'pelanggan', tingkat = 1 WHERE kode = 'diskon_member';
UPDATE fitur SET nama = 'Survei pelanggan', modul = 'pelanggan', tingkat = 1 WHERE kode = 'survei';
UPDATE fitur SET nama = 'Absensi karyawan', modul = 'pengguna', tingkat = 1 WHERE kode = 'absensi';
UPDATE fitur SET nama = 'Struk ringkas', modul = 'penjualan', tingkat = 2 WHERE kode = 'struk_ringkas';
UPDATE fitur SET nama = 'Cetak tiket dapur', modul = 'penjualan', tingkat = 2 WHERE kode = 'tiket_dapur';
UPDATE fitur SET nama = 'Catatan tambahan di struk', modul = 'penjualan', tingkat = 2 WHERE kode = 'catatan_struk';
UPDATE fitur SET nama = 'Service fee per tipe pesanan', modul = 'penjualan', tingkat = 2 WHERE kode = 'service_per_tipe_order';
UPDATE fitur SET nama = 'Status pesanan', modul = 'penjualan', tingkat = 2 WHERE kode = 'status_pesanan';
UPDATE fitur SET nama = 'DP untuk kasbon', modul = 'penjualan', tingkat = 2 WHERE kode = 'dp_kasbon';
UPDATE fitur SET nama = 'Nomor antrean', modul = 'penjualan', tingkat = 2 WHERE kode = 'nomor_antrean';
UPDATE fitur SET nama = 'Label metode pembayaran', modul = 'penjualan', tingkat = 2 WHERE kode = 'label_pembayaran';
UPDATE fitur SET nama = 'Logo usaha di struk', modul = 'penjualan', tingkat = 2 WHERE kode = 'logo_struk';
UPDATE fitur SET nama = 'Kelola bundling produk', modul = 'produk', tingkat = 2 WHERE kode = 'bundling';
UPDATE fitur SET nama = 'Pengingat kedaluwarsa produk', modul = 'stok', tingkat = 2 WHERE kode = 'pengingat_kedaluwarsa';
UPDATE fitur SET nama = 'Harga grosir', modul = 'produk', tingkat = 2 WHERE kode = 'harga_grosir';
DROP INDEX IF EXISTS ux_fitur_kunci_imogi;
ALTER TABLE fitur DROP COLUMN IF EXISTS kunci_imogi, DROP COLUMN IF EXISTS nomor_imogi;
UPDATE paket SET nama = 'Gratis' WHERE nama = 'Free';
UPDATE langganan SET paket_id = (SELECT id FROM paket WHERE nama = 'Starter') WHERE paket_id = (SELECT id FROM paket WHERE nama = 'Professional');
UPDATE permintaan_upgrade SET paket_tujuan_id = (SELECT id FROM paket WHERE nama = 'Starter') WHERE paket_tujuan_id = (SELECT id FROM paket WHERE nama = 'Professional');
DELETE FROM paket WHERE nama = 'Professional';
UPDATE paket SET nama = 'Pro' WHERE nama = 'Starter';
UPDATE paket SET nama = 'Bisnis', urutan = 2, harga_bulanan = 99000, harga_tahunan = 990000 WHERE nama = 'Enterprise';
INSERT INTO paket_fitur (paket_id, fitur_id) SELECT p.id, f.id FROM paket p JOIN fitur f ON f.tingkat <= p.urutan;
UPDATE paket_fitur pf SET batas = CASE p.nama WHEN 'Gratis' THEN 30 WHEN 'Pro' THEN 365 ELSE NULL END FROM paket p, fitur f WHERE pf.paket_id = p.id AND pf.fitur_id = f.id AND f.kode = 'laporan_dasar';
UPDATE toko SET jenis_usaha = 'fnb' WHERE jenis_usaha = 'CAF';
"""


def upgrade() -> None:
    for statement in split_statements(_UPGRADE_SQL):
        op.execute(statement)


def downgrade() -> None:
    for statement in split_statements(_DOWNGRADE_SQL):
        op.execute(statement)
