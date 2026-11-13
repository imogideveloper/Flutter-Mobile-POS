# Laporan Progres POS Makanan & Minuman untuk Lead

Disusun 2026-11-13. Acuan fitur: dokumen IMOGI (87 fitur, 4 paket). Cakupan aplikasi: modul Makanan & Minuman (7 jenis usaha, 64 fitur relevan).

## 1. Ringkasan

Sejak audit awal (2026-11-08), 13 nomor fitur dari daftar IMOGI mendapat versi pertama di aplikasi (4 di antaranya Release 1, 10 Future Release), sebagian besar fitur inti kafe yang sebelumnya belum ada (laporan keuangan dasar, pengeluaran, absensi, impor data, promo ulang tahun, margin produk). Fondasi sync juga diperbaiki: transaksi yang dibuat offline kini diterima server, dan sync berjalan otomatis.

**Yang harus dikatakan terus terang:** semua ini **baru terbukti lewat tes otomatis, belum diuji di HP**. Menurut aturan audit kita, belum ada fitur yang boleh disebut Done. Kami juga membangun beberapa fitur berstatus *Future Release* sebelum Release Scope dikonfirmasi (lihat bagian 5).

## 2. Angka sebelum dan sesudah

| | Awal audit | Sekarang |
|---|---|---|
| Fitur IMOGI relevan F&B: lengkap | 15 | 15 (tidak naik: belum ada uji HP) |
| sebagian | 24 | 33 |
| belum ada | 25 | 16 |
| Fitur inti Kafe & Kedai Kopi: lengkap / sebagian / belum ada | 11 / 18 / 17 | 11 / 25 / 10 |
| Paket di server | 3 paket, 32 fitur (salinan Qasir) | 4 paket IMOGI, 87 fitur |
| Tes otomatis | | Flutter 399 lulus; backend 438 lulus, 2 gagal karena lingkungan (folder fixture tidak ikut ke container) |
| Analisis kode | | 0 galat, 0 peringatan |
| Uji di HP | sebagian manual (2026-11-08) | belum ada untuk fitur baru |
| Pekerjaan | | 22 commit, 223 berkas, 17 migrasi database (0011-0017 baru) |

## 3. Fitur yang sudah ada versi pertamanya

Status semua: **kode selesai, lulus tes otomatis, belum diuji di HP**.

| Kelompok | Fitur (nomor IMOGI) | Catatan utama |
|---|---|---|
| Pesanan kafe | Varian dan tambahan produk (42); Status pesanan (26) dengan tahap Diantar, estimasi selesai, WhatsApp saat siap; Nomor antrian (34) dengan awalan dan angka awal; tiket dapur (kategori yang masuk tiket, cetak ulang) | Printer Bluetooth belum teruji (tidak ada perangkat) |
| Produk dan stok | Harga beli dan margin (37): penanda margin rendah, batas per outlet bawaan 50%; Impor produk CSV (38); Ekspor produk (39) | Impor hanya menambah, butuh internet |
| Pelanggan | Impor pelanggan CSV (53); Promo ulang tahun (56) beserta tanggal lahir pelanggan yang kini ikut sync | Promo dipilih kasir, belum otomatis |
| Keuangan | Catat pengeluaran (67); Laporan laba rugi (69); Rekap PPN/PB1 (73); Estimasi PPh Final (70) | Butuh internet; rumus belum divalidasi akuntan |
| Karyawan | Absensi masuk/keluar dan rekap (62); hak akses menu dan rute per peran; jalur keluar/ganti kasir | Tanpa foto, lokasi, jadwal |
| Fondasi | Perbaikan HPP checkout (HPP produk kini disimpan saat transaksi; sebelumnya selalu 0); Sync otomatis; server menerima transaksi offline (shift, kas shift, data induk hilang); lima bug diperbaiki di kode (BUG-004, 009, 012, 014, 015) | Bug berstatus Ready for Retest menunggu HP |

## 4. Yang belum ada (fitur inti kafe)

Settlement QRIS (74), jadwal shift dan cuti (63), payroll (76), chart of accounts dan jurnal (80), buku besar dan neraca (81), anggaran (82), ekspor ke software akuntansi (85), survei pelanggan (59), aset tetap (83), laporan konsolidasi (84). Menu Pengaturan versi IMOGI (11 tab) juga belum ada. QRIS dinamis dan printer Bluetooth terblokir (kunci Xendit dan perangkat belum ada).

## 5. Penyimpangan dan risiko (hasil audit)

1. **Urutan kerja terbalik.** Sembilan fitur berstatus *Future Release* (pengeluaran, laba rugi, pajak, impor/ekspor, absensi, impor pelanggan, promo ulang tahun) dibangun sebelum Release Scope (TASK-104) diputuskan. Fitur Release 1 yang masih terbuka: filter kategori di kasir, riwayat mutasi stok, catatan per item, tiket per stasiun, catatan tambahan di struk, pilih meja.
2. **Nol uji HP** untuk semua pekerjaan terbaru. Sembilan test case Critical (termasuk pembayaran TC-011 dan TC-012) belum dijalankan.
3. **Beberapa keputusan diambil sementara oleh pengembang** (daftar lengkap di `docs/perlu_konfirmasi.md`), terutama rumus laba rugi dan pajak serta matriks izin menu.
4. **Fitur keuangan, absensi, dan impor berbasis internet** padahal aplikasi dirancang offline-first.
5. Plugin native baru (`file_picker`) belum diuji di perangkat.

## 6. Keputusan yang dibutuhkan dari lead (urutan prioritas)

| # | Keputusan | Mengapa penting |
|---|---|---|
| 1 | Konfirmasi Release Scope (TASK-104): fitur Future Release di atas masuk Release 1 atau tidak | Menentukan apakah pekerjaan 2 hari terakhir terpakai |
| 2 | Validasi rumus keuangan oleh akuntan: laba rugi (belanja bahan tidak dikurangkan dua kali, refund belum dihitung), PPh Final 0,5% tanpa ambang bebas pajak | Angka dipakai pemilik usaha dan bisa salah bila tidak divalidasi |
| 3 | Matriks izin per menu dan apakah kasir boleh melihat Produk dan Laporan; perlu izin khusus "lihat harga beli"? | Menentukan siapa melihat HPP dan margin |
| 4 | Perilaku data induk yang hilang di server saat sync (pelanggan, tipe order, meja): saat ini transaksi tetap diterima | Memengaruhi integritas data transaksi |
| 5 | Apakah pengeluaran, absensi, dan impor harus bisa offline | Menentukan beban kerja sync tambahan |
| 6 | Pilih meja, catatan per item, pisah bill, layar dapur: tidak ada di dokumen IMOGI, tetap dibangun? | Fitur lama dari analisis awal |
| 7 | Harga dan kuota paket (harga di database masih contoh) | Dibutuhkan sebelum rilis |
| 8 | Sync saat aplikasi tertutup penuh (workmanager) masuk Release 1? | Risiko transaksi tertahan |
| 9 | Hasil pengujian di HP: siapa yang menguji dan kapan | Tanpa ini tidak ada fitur yang bisa naik ke Done |

## 7. Rencana yang diusulkan

1. Lead memutuskan Release Scope (nomor 1) dan validasi rumus (nomor 2).
2. Uji di HP: pasang APK dan jalankan 94 test case yang sudah disiapkan (TC-070 sampai TC-094 adalah rencana uji fitur baru, semua Not Tested).
3. Kerjakan butir Release 1 yang tersisa, bukan menambah fitur Future Release.
4. Siapkan rilis (keystore, alamat server produksi, rahasia JWT): ditunda atas keputusan sebelumnya.

## 8. Dokumen pendukung

- `docs/gap_imogi.md`: status 87 fitur dengan temuan per fitur.
- `docs/audit_alur_kerja.md`: audit kepatuhan dan laporan per task, termasuk bagian H (audit kemajuan).
- `docs/perlu_konfirmasi.md`: seluruh keputusan sementara dan temuan yang menunggu konfirmasi.
- `docs/dokumentasi-qa/`: tiga workbook (Tracker, QA, UAT), diperbarui 2026-11-13.
- Cabang kode: `feature/alur-kafe-imogi` (22 commit; belum digabung ke `main`).
