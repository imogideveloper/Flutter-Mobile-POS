# Temuan dan Keputusan yang Perlu Konfirmasi

Dibuat 2026-11-12. Daftar ini mengumpulkan semua hal yang **saya putuskan sementara sendiri**, **tidak bisa saya pastikan**, atau **bertentangan antar sumber**, supaya tidak hilang di antara dokumen lain. Tidak satu pun di sini boleh dianggap disetujui sampai ada konfirmasi tertulis dari pihak yang berwenang.

Aturan baca: **Sementara** = perilaku yang sekarang dipakai di kode. **Dampak bila salah** = apa yang harus diubah.

---

## A. Keputusan lead (produk, rilis, paket)

| # | Hal | Sementara | Dampak bila salah | Sumber |
|---|---|---|---|---|
| A1 | Release Scope TASK-103/104/105 belum diputuskan | Tidak diubah sepihak; pekerjaan diurutkan fondasi dulu | Urutan kerja bisa berubah | audit_alur_kerja.md |
| A2 | Harga dan kuota paket (TASK-119): dokumen IMOGI tidak memuat harga | Harga contoh (Rp 59.000 dan Rp 99.000) | Ubah katalog dan migrasi harga | temuan_audit.md bag. 9 |
| A3 | Perilaku data induk yang hilang di server saat sync (pelanggan, tipe order, meja) | Server mengosongkan rujukan itu dan menerima transaksi; poin tukar dinolkan | Bisa menerima transaksi yang seharusnya ditolak, atau sebaliknya | sync/checkout_service |
| A4 | Nilai bawaan `tampil_logo` | Bawaan menyala | Paket Gratis tidak bisa simpan pengaturan bila diubah menyala (BUG-012) | outlet.py |
| A5 | Sync saat aplikasi tertutup penuh (workmanager) masuk Release 1? | Hanya sync di latar depan (buka, resume, koneksi pulih, 5 menit, setelah bayar) | Transaksi bisa tertahan bila HP rusak sebelum aplikasi dibuka lagi | auto_sync.dart |
| A6 | Jalur masuk karyawan di perangkat baru | Menunggu pemilik memasangkan perangkat; tombol PIN disembunyikan | Perlu kode undangan atau jalur lain | BUG-009 |
| A7 | Aplikasi hanya modul F&B (7 jenis usaha) dari 43 jenis usaha IMOGI | Dipakai begitu | Cakupan fitur berubah | gap_imogi.md |
| A8 | Paket tersedia di server: katalog IMOGI 4 paket, tetapi data seed tes memakai 3 paket lama (Gratis, Pro, Bisnis) dan kode fitur lama | Tes memakai seed lama ditambah kode IMOGI satu per satu (`expenses`, `profit_loss`, `tax_recap`, `tax_pph`) | Tes bisa lulus padahal katalog produksi berbeda; perlu menyamakan seed tes dengan migrasi 0010 | backend/app/core/seed.py |

## B. Hak akses dan peran (Fase 4)

| # | Hal | Sementara | Dampak bila salah |
|---|---|---|---|
| B1 | Matriks izin per menu Lainnya tidak dirinci dokumen IMOGI | Shift/kas = `shift.buka_tutup`; Pelanggan = `pelanggan.kelola`; Stok = `stok.kelola`; Kategori dan Varian = `produk.kelola`; Outlet-struk, Metode bayar, Tipe pesanan, Level member, Paket langganan = `pengaturan.kelola`; Pajak dan Promo = `promo.kelola`; Karyawan = `pengguna.kelola` | Salah peran bisa melihat menu yang bukan haknya, atau kasir kehilangan akses yang perlu |
| B2 | Kasir tidak melihat tab Produk dan Laporan | Disembunyikan (izin `produk.kelola`, `laporan.lihat`) | Kasir kafe kecil sering perlu cek harga/stok; ubah izin role Kasir, bukan kode |
| B3 | Karyawan asal server memakai role sistem (roleId tidak diganti) | Bila role tidak dikenali, izin kosong dan menu terbatas tersembunyi (gagal aman) | Karyawan bisa tidak melihat menu yang seharusnya; **belum diuji di HP** |
| B4 | Keranjang dan pesanan belum disimpan tidak dibersihkan saat ganti kasir | Dibiarkan | Kasir berikutnya melihat keranjang kasir sebelumnya |
| B5 | Sesi hanya di memori (menutup aplikasi = pilih akun lagi) | Perilaku lama | Mungkin perlu kunci layar otomatis (IMOGI memilikinya, aplikasi belum) |
| B6 | Daftar 18 hak akses IMOGI dan peran bawaan Barista & Dapur belum dicocokkan | Hanya 15 izin dan 3 peran (Owner, Manajer, Kasir) | Lihat gap_imogi.md |
| B7 | Penjagaan rute hanya untuk halaman yang saya daftarkan | Rute lain (Kasir, Riwayat, Status pesanan, Printer) sengaja terbuka | Bila ada rute baru, harus didaftarkan ke `IzinGuard` |

## C. Rumus keuangan dan pajak (perlu validasi akuntan atau konsultan pajak)

| # | Hal | Sementara |
|---|---|---|
| C1 | Laba rugi: pendapatan = subtotal − diskon, tanpa pajak/service | Pajak/service dipungut ditampilkan sebagai catatan |
| C2 | HPP = `hpp_satuan` × qty yang **dikirim HP** per item (dari HPP produk) | Toko yang tidak mengisi HPP produk melihat laba terlalu besar |
| C3 | Belanja bahan **tidak dikurangkan** lagi dari laba (dianggap sudah di HPP) | Bila HPP kosong, belanja bahan justru satu-satunya biaya bahan; laba tampak terlalu besar |
| C4 | Refund belum mengurangi pendapatan | Laba bisa terlalu besar bila banyak refund |
| C5 | Dasar akrual sederhana (tanggal transaksi/pengeluaran), bukan kas | Berbeda dari kas shift |
| C6 | PPh Final: tarif 0,5% dipasang tetap, dasar = subtotal − diskon | Ambang peredaran bebas pajak (Rp 500 juta/tahun untuk orang pribadi) dan masa berlaku tarif **tidak dihitung**, jadi bisa lebih besar dari yang terutang |
| C7 | Rekap pajak mengelompokkan per nama dan tarif; pajak tanpa master dianggap pajak biasa kecuali nama diawali "Service" | Pajak yang diganti nama tampil sebagai baris berbeda |
| C8 | Semua angka ini bukan laporan keuangan/pajak resmi | Wajib dikonsultasikan sebelum dipakai untuk pelaporan |

## D. Pengeluaran, estimasi, WhatsApp

| # | Hal | Sementara |
|---|---|---|
| D1 | Pengeluaran **online-only** (langsung ke server) | Pencatatan tanpa sinyal tidak bisa; butuh keputusan antrian sync offline |
| D2 | Izin pengeluaran memakai `laporan.lihat` (Owner/Manajer; kasir tidak bisa) | Izin khusus `pengeluaran.kelola` belum ada di katalog izin |
| D3 | Sembilan kategori pengeluaran disusun dari kebutuhan F&B, bukan daftar resmi IMOGI | Ganti daftar di server dan aplikasi |
| D4 | Estimasi selesai hanya satu angka per outlet | IMOGI mungkin menuntut estimasi per produk |
| D5 | Pesan WhatsApp saat siap dikirim manual oleh kasir, bukan otomatis | Perlu WhatsApp API bila ingin otomatis |
| D6 | **Temuan, belum diperbaiki:** tombol "Kirim WhatsApp" di struk memanggil helper tanpa nomor pelanggan, jadi selalu memakai menu bagikan walau pelanggan punya nomor | Apakah disengaja? (`StrukPage._kirimWhatsApp`) |

## E. Administrasi workbook QA/UAT/Task

| # | Hal |
|---|---|
| E1 | Fitur yang saya tambahkan belum punya ID TASK/FEAT/TC di workbook (tidak saya karang): cetak ulang tiket, tahap Diantar, awalan/angka awal antrian, kategori masuk tiket dapur, estimasi selesai, WhatsApp saat siap, penjagaan izin menu, jalur logout di Lainnya, pengeluaran (no. 67), laba rugi (no. 69), rekap pajak (no. 73 dan 70). Perlu ID dari lead/QA. |
| E2 | Baris dummy masih ada (BUG-901..903, RUN-901..903, RETEST-901, UAT-RUN-901/902); bukan hasil nyata. |
| E3 | Konflik antar sumber: BUG-019 dan BUG-020 deskripsi bertukar; UAT-009 vs UAT-012; TASK-022..027 ada di Timeline. Didokumentasikan, belum diputuskan. |
| E4 | Skrip pembangkit Excel asli hilang; saat ini diperbarui dengan skrip tambal (`_perbarui_catatan.py`, `_perbarui_status.py`). |
| E5 | Bug berstatus Ready for Retest menunggu uji HP: BUG-004, 009, 012, 013, 014, 015, 018 sampai 021. BUG-012 tidak bisa direproduksi di masa trial semua paket. |
| E6 | TC Critical belum dijalankan: TC-011, 012, 041, 042, 057, 058, 061, 065, 068. |
| E7 | Email commit disusun dari nama (`nurul-izzhh@users.noreply.github.com`), bukan akun GitHub terverifikasi. |

## F. Belum bisa dikerjakan atau diuji

| # | Hal |
|---|---|
| F1 | **Semua** perilaku di HP untuk fitur 2026-11-10 sampai 2026-11-12 belum diuji (tes otomatis bukan bukti Done). |
| F2 | Printer Bluetooth belum teruji (tidak ada printer); kunci Xendit kosong (QRIS dinamis Blocked). |
| F3 | Tes backend `test_harga_fixtures` dan `test_refund_fixtures` gagal di container karena folder `shared/fixtures` tidak ikut (masalah lingkungan, bukan kode). |
| F4 | Tidak ada Python di Windows; tes backend dan skrip Excel dijalankan lewat container `api`. |
| F5 | Empat risiko rilis Play Store ditunda (keystore, alamat server produksi, dll.), lihat temuan_audit.md bag. 6. |

---

## Cara memakai daftar ini

1. Bawa bagian A, B, C, D ke lead; E ke QA/PM; F untuk perencanaan.
2. Saat dijawab, ubah kolom "Sementara" menjadi keputusan resmi (tanggal dan siapa yang memutuskan) dan sesuaikan kode.
3. Jangan hapus baris; tandai **Diputuskan** supaya riwayatnya tetap ada.

---

## Tambahan 2026-11-12 (impor dan ekspor produk)

| # | Hal | Sementara |
|---|---|---|
| G1 | Format impor CSV, bukan .xlsx | Mendukung .xlsx butuh paket tambahan |
| G2 | Impor hanya menambah; SKU/barcode ganda ditolak, tidak memperbarui produk lama | Perlu keputusan apakah "perbarui bila SKU sama" dibutuhkan |
| G3 | Kategori yang belum ada dibuat otomatis dari nama di berkas | Salah ketik menghasilkan kategori baru |
| G4 | Dependensi baru `file_picker` (plugin native) | Perlu diuji di HP; menambah ukuran dan izin berkas aplikasi |
| G5 | Impor produk butuh internet (langsung ke server) | Selaras pola data master lain, tapi bukan offline-first |

## Tambahan 2026-11-12 (absensi)

| # | Hal | Sementara |
|---|---|---|
| H1 | Absen tanpa foto dan tanpa lokasi (GPS) | Kolom di tabel sudah ada; IMOGI mungkin mewajibkan |
| H2 | Tidak ada jam kerja/jadwal, jadi tidak ada status terlambat (selalu "hadir"); jadwal shift mingguan (no. 63) belum ada | Perlu aturan keterlambatan |
| H3 | Waktu absen memakai jam server, wajib online | Absensi offline belum didukung |
| H4 | Rekap semua karyawan untuk izin `laporan.lihat`; menu Absensi terlihat semua peran | Perlu konfirmasi izin khusus absensi |
| H5 | **Temuan:** laporan penjualan lama (`/laporan/penjualan` dll.) menerima datetime dari klien apa adanya, belum diaudit untuk bug batas hari/zona waktu seperti yang ditemukan pada absensi | Audit terpisah |
