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
| E1 | **Dikoreksi 2026-11-13:** delapan fitur IMOGI baru (no. 38, 39, 53, 62, 67, 69, 70, 73) SUDAH punya ID FEAT di Feature Inventory (FEAT-035, 034, 036, 038, 076, 077, 078, 080) dan kini berstatus In Progress; test case baru TC-070 sampai TC-088 dan skenario UAT-016 sampai UAT-019 ditambahkan sebagai rencana (Not Tested / Not Prepared, ID berurutan yang boleh diganti QA/lead). Yang BELUM punya ID: cetak ulang tiket dapur, tahap Diantar, awalan/angka awal antrian, kategori masuk tiket dapur, estimasi selesai, WhatsApp saat siap, penjagaan izin menu, jalur logout (kini dicatat di Notes FEAT-041, FEAT-028, FEAT-050). **Belum ada TASK** untuk fitur-fitur ini di Task Tracker: ID TASK, PIC, dan tanggal perlu ditetapkan lead (tidak saya karang). |
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
| F3 | **Selesai 2026-11-14:** `test_harga_fixtures` dan `test_refund_fixtures` ternyata gagal hanya karena folder `shared/` tidak ikut ke container uji (jalur `/shared/fixtures`); setelah folder itu disalin, seluruh 474 tes backend lulus. Bukan masalah kode. Untuk uji di container: salin `shared` ke `/shared` bersama `tests` |
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

## Tambahan 2026-11-13 (impor pelanggan)

| # | Hal | Sementara |
|---|---|---|
| I1 | Impor pelanggan hanya menambah; nomor HP yang sudah terdaftar ditolak, tidak memperbarui data lama | Perlu keputusan "perbarui bila nomor sama" |
| I2 | Nomor HP dinormalkan ke angka saja; format 0812/62812/+62812 dianggap satu nomor; angka 0 yang hilang karena Excel dipulihkan secara heuristik | Heuristik bisa keliru untuk nomor non-seluler Indonesia |
| I3 | Impor tidak mengisi poin, level member, atau batas kasbon | Pelanggan lama dengan saldo poin harus dimigrasikan terpisah |

## Tambahan 2026-11-13 (harga beli dan margin, IMOGI no. 37)

| # | Hal | Sementara |
|---|---|---|
| J1 | "Hak akses lihat harga beli": belum ada izin khusus; HPP dan margin hanya terlihat di halaman Produk yang dijaga izin `produk.kelola` (Owner/Manajer), kasir tidak melihatnya | Daftar 18 hak akses IMOGI belum dicocokkan; bila perlu izin `produk.lihat_hpp` terpisah, butuh keputusan lead dan perubahan seed izin |
| J2 | Batas margin bawaan 50% untuk semua jenis usaha F&B (dari panduan Pengaturan Stok) | Panduan hanya menyebut 50% untuk F&B; bawaan per jenis usaha belum dibedakan |
| J3 | Rumus margin = (harga jual - HPP) / harga jual; tepat di batas dianggap aman | Bila IMOGI memakai markup (dari HPP), angkanya berbeda |
| J4 | HPP kosong ditandai "HPP belum diisi" dan tidak dihitung sebagai margin rendah | Alternatif: menganggap margin 100% |
| J5 | Batas margin diletakkan di Pengaturan struk (halaman pengaturan outlet yang ada), padahal panduan menempatkannya di tab Stok/Katalog | Pindah saat Menu Pengaturan IMOGI dibangun |

## Tambahan 2026-11-13 (promo ulang tahun, IMOGI no. 56)

| # | Hal | Sementara |
|---|---|---|
| K1 | Promo ulang tahun dipilih manual oleh kasir; tidak otomatis | Penerapan otomatis menyentuh perhitungan harga; perlu keputusan |
| K2 | Syarat "berulang tahun hari ini" dicek hanya di HP (penjaga di keranjang); server tidak memeriksa saat checkout | Transaksi dari HP yang dimodifikasi bisa memakai promo itu tanpa syarat |
| K3 | Hari ulang tahun = bulan dan tanggal sama dengan hari ini; yang lahir 29 Februari dirayakan 28 Februari di tahun bukan kabisat | IMOGI mungkin memakai rentang (mis. seminggu atau sebulan) |
| K4 | Tanggal lahir di HP disimpan sebagai yyyymmdd (kolom lama bermakna epoch tidak pernah terisi) | Tidak ada data lama yang terpengaruh |
| K5 | Tanggal lahir diisi manual atau lewat impor CSV; tidak ada pengingat ke pelanggan (WhatsApp/SMS) | Pengiriman pesan ulang tahun belum ada (terkait no. 57 kirim WA massal) |

## Tambahan 2026-11-14 (cacat HPP dan laporan margin, IMOGI no. 72)

| # | Hal | Sementara |
|---|---|---|
| L1 | **Temuan cacat:** sebelum 2026-11-14 aplikasi tidak pernah menyimpan HPP pada item transaksi (`hppSatuan` selalu 0). Akibatnya laba kotor di tab Laporan, laba rugi (no. 69), dan HPP yang dikirim ke server untuk semua transaksi dari HP bernilai 0 | Diperbaiki di kode: HPP produk disimpan sebagai snapshot saat checkout |
| L2 | **Data lama tidak dikoreksi:** transaksi yang sudah ada (di HP maupun server) tetap HPP 0, jadi laba rugi periode lama menganggap barang tanpa modal | Perlu keputusan backfill (mengisi HPP produk saat ini ke transaksi lama) atau menandai periode lama tidak akurat; tidak saya lakukan otomatis karena mengubah data transaksi |
| L3 | Pengujian laba rugi (no. 69) sebelumnya hanya mengirim `hpp_satuan` lewat API, sehingga cacat L1 tidak tertangkap tes otomatis | Tes snapshot HPP di sisi aplikasi kini ada (`laporan_margin_test.dart`) |
| L4 | HPP yang disimpan = HPP produk saat checkout; HPP tambahan/varian tidak diikutkan, jadi margin item dengan tambahan berbayar sedikit terlalu tinggi | Perlu aturan HPP untuk tambahan |
| L5 | Kartu HPP & margin dihitung dari data HP (offline), bukan dari server; angkanya bisa berbeda dari laporan server bila perangkat lain juga menjual | Selaras dengan laporan lokal yang sudah ada |
| L6 | FEAT-048 "Laporan F&B" berstatus Future Release; kartu ini menambah jumlah fitur Future Release yang dikerjakan menjadi sepuluh | Lihat audit_alur_kerja.md H2 |
| L7 | Dua definisi "laba kotor": ringkasan Laporan dan `/laporan/penjualan` = (harga satuan - HPP) x qty tanpa memotong diskon; laporan laba rugi = subtotal - diskon - HPP | Saat ada diskon/promo, laba kotor di Laporan lebih besar daripada di Laba rugi; perlu satu definisi resmi |

## Tambahan 2026-11-14 (pemisahan fitur per jenis usaha dan jadwal shift)

| # | Hal | Sementara |
|---|---|---|
| M1 | **Pemisahan fitur per jenis usaha (kafe, katering, restoran, dst.) belum diterapkan.** Jenis usaha dipilih saat daftar dan disimpan (`toko.jenis_usaha`, 7 kode IMOGI: CAF, RES, CAT, BRD, FRZ, BEV, STL). Tabel `fitur_kebutuhan` di database sudah memuat klasifikasi inti/opsional/tidak relevan untuk tiap fitur per jenis usaha (mis. Kafe 46 inti, Katering 34 inti), tetapi **tidak ada kode server maupun aplikasi yang membacanya** | Semua jenis usaha melihat menu dan perilaku yang sama. Satu-satunya pembeda yang ada: alur Status pesanan katering (Dipesan, Dimasak, Siap kirim, Dikirim, Selesai) |
| M2 | Yang belum dibuat sebagai akibat M1: menyembunyikan menu fitur "tidak relevan" per jenis usaha, menandai fitur opsional, dan nilai bawaan pengaturan per jenis usaha (pajak PB1 ditambahkan, service 5% makan di tempat, struk ringkas, nomor antrian menyala untuk kafe/minuman/food court/roti, tiket dapur otomatis, modal awal shift Rp 300.000) | Pengaturan harus dibuat manual oleh pemilik |
| M3 | Perlu keputusan lead: menyembunyikan menu "tidak relevan" bisa menyembunyikan fitur yang dibutuhkan pemilik; apakah cukup diberi tanda, atau benar-benar disembunyikan sesuai dokumen IMOGI | Menentukan perancangan tahap berikutnya |
| N1 | Jadwal shift: hanya tiga pola (libur, pagi 07:00-15:00, siang 14:00-22:00) dengan jam bawaan tetap di layar; server sudah menerima jam kustom, belum ada isian di layar; shift lintas tengah malam belum didukung | IMOGI menyebut shift pagi/siang saja; belum jelas apakah malam dibutuhkan |
| N2 | Toleransi terlambat 10 menit dipasang tetap | IMOGI mungkin mengaturnya per outlet |
| N3 | Jadwal dan persetujuan cuti memakai izin `laporan.lihat` (Owner/Manajer); pengajuan sendiri tidak boleh diputuskan sendiri | Perlu izin khusus bila Manajer tidak boleh menyetujui cuti |
| N4 | Cuti yang disetujui hanya ditampilkan di Jadwal; belum menghalangi absen atau menandai Izin/Sakit pada rekap absensi | Perlu aturan hubungan cuti dan absensi |
| N5 | Tukar jadwal (IMOGI no. 63) belum ada | Tahap berikutnya |

## Tambahan 2026-11-15 (logout usaha dan akun Administrator, permintaan lead)

| # | Hal | Sementara |
|---|---|---|
| O1 | Logout usaha hanya untuk peran **Owner** (menu Lainnya > "Keluar dari usaha"), baik di layar maupun di server (`POST /auth/logout` menolak 403 selain Owner sistem) | Perlu konfirmasi: apakah Manajer boleh juga |
| O2 | Logout ditahan bila masih ada transaksi/pembayaran/pembatalan/status pesanan yang belum terkirim ke server (setelah mencoba sync); tidak ada opsi "paksa keluar" | Bila lead menginginkan paksa keluar, data belum terkirim akan hilang |
| O3 | Logout menghapus SELURUH data lokal usaha dan token di HP (data di server tetap). Pengaturan di penyimpanan lain (mis. profil toko di penyimpanan aman) belum ikut dibersihkan | Perlu dicek di HP sungguhan |
| O4 | Pencabutan di server: perangkat dinonaktifkan sehingga refresh token dan login PIN perangkat itu ditolak; access token yang beredar kedaluwarsa sendiri. Bila HP offline saat logout, pencabutan server dilewati (best-effort) | Token lama baru mati setelah kedaluwarsa |
| O5 | Akun Administrator: tabel `akun_admin` (email, password bcrypt), login `POST /admin/auth/login`, token bertipe `admin` yang tidak berlaku di endpoint toko. **API key statis tetap berlaku** sebagai jalur peralihan dan satu-satunya cara membuat admin pertama (`POST /admin/akun`) | Perlu diputuskan kapan API key dimatikan; kata sandi admin pertama dibuat operator, tidak disimpan di repo |
| O6 | Belum ada: ganti/lupa kata sandi admin, batas percobaan login, peran admin berjenjang, dan layar login admin (dashboard) | Tahap 2 |

## Tambahan 2026-11-15 (dashboard Administrator di Flutter, permintaan lead)

| # | Hal | Sementara |
|---|---|---|
| P1 | Dashboard dibangun di **Flutter** (bukan React): login admin dari layar OTP ("Masuk sebagai Administrator") lalu 3 tab: Ringkasan, Usaha, Fitur; filter 7 jenis usaha F&B. Sesi admin hanya di memori (tutup aplikasi = login lagi) | Halaman web terpisah (React atau Flutter Web) ditunda sesuai arahan "cukup Flutter dulu" |
| P2 | **Cara memperbarui status fitur:** ubah `backend/app/data/status_fitur.json` (kunci = nomor IMOGI) bersamaan dengan `docs/gap_imogi.md` setiap fitur selesai; status tersalin ke database tiap server menyala. Nilai: belum, sedang, sudah, tidak_relevan | Tes `test_berkas_status_nyata_valid_dan_cocok_dengan_gap_imogi` mengunci jumlah 15/34/15/23, ubah angkanya bersama berkas |
| P3 | "Sudah" = kode selesai dan lulus tes otomatis. `uji_hp` selalu false sampai ada bukti uji di HP; dashboard menampilkan "Lulus uji di HP: 0" | Jangan diisi true tanpa bukti |
| P4 | Pada filter jenis usaha, fitur dengan kebutuhan `na` untuk jenis itu ditampilkan **Tidak relevan** walau kodenya ada (mis. kafe: 26, katering: 29), sedangkan tanpa filter angkanya 23 (tidak relevan untuk semua 7 jenis) | Perlu dikonfirmasi lead: apakah hitungan ini yang diinginkan |
| P5 | Paket yang dipakai usaha dihitung **paket efektif** (selama trial = paket tertinggi), dan paket langganan sebenarnya tampil terpisah di daftar usaha | Di dev, satu-satunya usaha tampil "Enterprise" karena trial 4 bulan |
| P6 | Pengguna dihitung = karyawan aktif per usaha. "Akun yang download" belum ada hitungan unduhan (butuh data Play Store); yang ada baru usaha terdaftar dan pengguna | Perlu didefinisikan bersama lead |
| P7 | **Cacat yang ditemukan lewat uji ke Postgres:** migrasi 0020 (akun_admin) tidak punya kolom `deleted_at` sehingga membuat akun admin gagal di Postgres walau tes SQLite lulus; diperbaiki migrasi 0022. Tes backend memakai SQLite dari model, jadi selisih model dan migrasi tidak tertangkap | Perlu uji migrasi ke Postgres sungguhan di CI |

## Tambahan 2026-11-15 (aplikasi Windows, permintaan lead)

| # | Hal | Sementara |
|---|---|---|
| Q1 | Aplikasi Windows belum bisa dibuild: **Visual Studio (C++) belum terpasang** di komputer pengembangan; kode dan tata letak sudah disiapkan dan lulus tes otomatis, belum pernah dijalankan di Windows | Pengguna perlu memasang Visual Studio (lihat `docs/windows_desktop.md`) |
| Q2 | Pemindai kamera tidak tersedia di Windows; diganti dialog ketik/scan (pemindai USB/Bluetooth sebagai keyboard) | Perlu konfirmasi apakah cukup |
| Q3 | Sync latar belakang (`workmanager`) tidak mendukung Windows; saat ini tidak dipakai di kode, sync berjalan saat aplikasi terbuka | Perlu diputuskan bila sync saat aplikasi tertutup masuk Release 1 |
| Q4 | Printer Bluetooth di Windows belum teruji | Perlu perangkat |
| Q5 | Belum ada installer (MSIX/Inno Setup), pintasan keyboard, dan optimasi mouse | Tahap lanjutan |

## Tambahan 2026-11-15 (kartu/EDC, IMOGI no. 13)

| # | Hal | Sementara |
|---|---|---|
| R1 | "Wajib no. referensi" diterapkan di layar kasir saja (HP). Server tetap menerima transaksi tanpa referensi (push offline tidak boleh ditolak), sama seperti limit bon | Perlu konfirmasi bila server harus menolak |
| R2 | Aturan sementara: bila wajib, no. referensi harus diisi; untuk kartu, 4 digit akhir juga wajib dan harus tepat 4 angka; untuk transfer/e-wallet hanya no. referensi | Dokumen IMOGI hanya menyebut "no. referensi/4 digit" |
| R3 | Pengaturan wajib tidak diterapkan pada bayar campur (split), yang belum punya isian referensi per baris | Susulan |
| R4 | Jenis kartu (debit/kredit) dan daftar mesin EDC belum dibuat | Perlu keputusan: cukup lewat nama metode (mis. "Kartu BCA") atau daftar mesin tersendiri |

## Tambahan 2026-11-15 (diskon manual per item, IMOGI no. 3) dan temuan keamanan

| # | Hal | Sementara |
|---|---|---|
| S1 | **Temuan keamanan (sudah ada sebelumnya) - DIPERBAIKI 2026-11-15:** seed lokal membuat pengguna "Owner (default)" ber-PIN `000000` (`lib/core/database/seed.dart`), dan baris itu **tidak dihapus setelah perangkat dipasangkan** (hanya metode bayar yang direkonsiliasi). Siapa pun yang tahu PIN itu bisa menyetujui diskon, void, refund, dan mengubah harga atas nama owner | Owner bawaan kini dinonaktifkan dan PIN-nya dihapus otomatis saat sync pull membawa pengguna server yang aktif dan ber-PIN (tes lewat jalur sync dan DAO). Bila belum ada pengguna server ber-PIN, Owner bawaan dibiarkan agar perangkat tidak terkunci. Belum diuji di HP |
| S2 | Aturan sementara diskon manual: hanya per item; butuh izin `transaksi.diskon` (Owner/Manajer) atau PIN approver; Kasir selalu diminta PIN. Server tetap menolak 403 bila online tanpa penyetuju sah, dan menerima push offline dengan audit | IMOGI menyebut "batas diskon dengan PIN owner" dan "izin diskon per item": batas persen untuk kasir tanpa PIN belum dibuat |
| S3 | Tombol cepat tetap 5/10/15/20%, belum bisa diatur per usaha | Perlu konfirmasi lead |
| S4 | Diskon manual hilang bila pesanan tersimpan (open bill) dibuka kembali, karena harga dihitung ulang dari awal | Susulan |
| S5 | Diskon persen dihitung dari nilai baris di keranjang; bila harga grosir/outlet lebih murah, diskon dibatasi tidak melebihi nilai baris | Perlu uji dengan harga grosir di HP |

## Tambahan 2026-11-15 (status pajak usaha dan preset pajak, IMOGI no. 4)

| # | Hal | Sementara |
|---|---|---|
| T1 | "Usaha kena pajak / tidak kena pajak" tidak disimpan sebagai pengaturan tersendiri: dihitung dari ada/tidaknya pajak (bukan service charge) yang aktif. Saklar di daftar Pajak & Service mengirim perubahan aktif ke server per pajak, sehingga hitungan server dan HP tetap sama | Bila lead ingin status usaha terpisah (mis. nomor PKP), perlu kolom dan aturan hitung baru di kedua sisi |
| T2 | Saklar mati menonaktifkan pajak, bukan menghapusnya, dan pajak nonaktif kini tampil di daftar dengan label Nonaktif. Service charge tetap berlaku | Perlu konfirmasi |
| T3 | Preset form: PB1 10% (ditambahkan), PPN 11% (ditambahkan), Service 5%. Nilai resmi dan cara hitung bawaan per jenis usaha belum ditetapkan | Perlu validasi (PB1 biasanya 10% di daerah, tarif bisa berbeda); bawaan per jenis usaha menunggu Batch B |

## Tambahan 2026-11-15 (terima order, bayar belakangan, IMOGI no. 27)

| # | Hal | Sementara |
|---|---|---|
| U1 | "Terima Order" dibuat sebagai transaksi sungguhan dengan penanda `bayar_belakangan` (server: kolom baru, migrasi 0024), BUKAN kasbon: tanpa pelanggan wajib, tanpa fitur kasbon, tanpa jatuh tempo, tidak masuk daftar piutang pelanggan. Total_bayar wajib 0 | Perlu konfirmasi lead: apakah order yang belum dibayar sudah dihitung sebagai penjualan di laporan (saat ini ya, sama dengan kasbon) |
| U2 | Pelunasan memakai endpoint cicilan yang sudah ada; kas masuk ke shift yang sedang terbuka saat dibayar, bukan shift saat order diterima | Sesuai perilaku kasbon |
| U3 | Pelunasan hanya untuk metode manual (tunai, kartu, transfer, dst.), belum QRIS dinamis; belum ada kembalian untuk tunai (jumlah dicatat sebesar yang dibayarkan, maksimal sisa) | Susulan |
| U4 | Penukaran poin ditolak saat Terima Order (poin hanya saat membayar) | Perlu konfirmasi |
| U5 | "Pilihan kapan membayar" (di meja, setelah makan, nanti) dan nota order khusus belum dibuat; struk menampilkan "Order diterima, bayar nanti" dan sisa tagihan | Perlu rincian dari dokumen IMOGI |

## Tambahan 2026-11-15 (biaya layanan per tipe pesanan, IMOGI no. 6)

| # | Hal | Sementara |
|---|---|---|
| V1 | **Risiko paket:** Service Charge 5% bawaan Kafe/Restoran hanya dibatasi ke "Makan di tempat" bila fitur `service_per_tipe_order` (paket Enterprise) aktif. Selama masa trial (paket tertinggi) berlaku; setelah trial di paket lebih rendah, aturan lama berlaku: service yang aktif dikenakan pada SEMUA tipe pesanan, termasuk bawa pulang | Perlu keputusan lead: apakah bawaan tetap aktif, atau dimatikan otomatis saat fitur tidak tersedia |
| V2 | Bawaan hanya untuk toko yang mendaftar setelah perubahan ini. Toko yang sudah ada tidak diubah (tipe pesanan lokal mereka tetap dipakai) | Perlu skrip migrasi bila ingin diterapkan ke toko lama |
| V3 | Tipe pesanan sekarang bersumber dari server (sebelumnya hanya seed lokal HP). Pada pull pertama dari awal, bawaan lokal dinonaktifkan; transaksi lama yang merujuknya tetap utuh | Perlu diuji di HP bersih dan HP yang sudah berisi data |
| V4 | Hanya Kafe (CAF) dan Restoran (RES) mendapat service bawaan; usaha lain (katering, roti, dst.) tidak, sesuai dokumen IMOGI | Perlu konfirmasi bila jenis lain juga perlu |

## Tambahan 2026-11-15 (label jenis pembayaran, IMOGI no. 18)

| # | Hal | Sementara |
|---|---|---|
| W1 | Dua konsep "label" dipisah: ubah NAMA/urutan metode bayar (sudah ada) dan LABEL TUJUAN baru (GoPay, OVO, ShopeePay, bank) untuk rekonsiliasi. Label tujuan disimpan sebagai daftar dipisah koma per metode (maks. 10 label, maks. 30 karakter) | Perlu konfirmasi bentuk yang diinginkan lead |
| W2 | Bila metode punya label tujuan, kasir WAJIB memilih satu saat menerima pembayaran (kartu, transfer, e-wallet). Server tidak menolak pembayaran tanpa label (push offline tidak boleh ditolak) | Perlu konfirmasi: wajib atau opsional |
| W3 | Label tidak berlaku untuk QRIS statis (halaman sendiri), bayar campur (split), maupun pelunasan order/kasbon | Susulan |
| W4 | Baris laporan memakai bentuk "Qris · GoPay" (nama metode, titik tengah, label); sama di HP dan server. Rekonsiliasi dengan mutasi pihak ketiga (settlement, IMOGI no. 74) belum ada | Perlu konfirmasi format laporan |
| W5 | Menyimpan label butuh paket yang memuat fitur label_pembayaran (Enterprise); paket lebih rendah ditolak 403 | Sesuai katalog IMOGI |

## Tambahan 2026-11-15 (gaya logo struk, IMOGI no. 24)

| # | Hal | Sementara |
|---|---|---|
| X1 | Tiga gaya siap pakai dibuat otomatis dari 1-2 huruf awal nama usaha: lingkaran (isi hitam, huruf putih), cincin (garis, huruf hitam), inisial (huruf saja). Hitam-putih murni untuk printer thermal. Bentuk dan huruf diperkirakan dari deskripsi dokumen IMOGI, belum dicocokkan dengan contoh visualnya | Perlu konfirmasi lead terhadap desain IMOGI |
| X2 | Gaya otomatis digerbang fitur `logo_struk` (Enterprise) seperti saklar logo; bawaan tetap logo unggahan sehingga paket Gratis bisa menyimpan pengaturan lain (BUG-012 tetap aman). Gaya ditolak 403 hanya bila diubah ke gaya otomatis tanpa fitur | Sesuai katalog |
| X3 | Cetak ulang dari riwayat memakai gaya logo pada pengaturan SAAT INI, bukan gaya saat transaksi (hanya tampil/tidaknya logo yang dibekukan di snapshot struk) | Perlu konfirmasi |
| X4 | Belum diuji di printer Bluetooth sungguhan (tidak ada perangkat): ukuran 240 px dan ambang hitam-putih bisa perlu disesuaikan untuk kertas 58 mm | Terblokir perangkat |

## Tambahan 2026-11-16 (QRIS statis dari gambar usaha, IMOGI no. 10)

| # | Hal | Sementara |
|---|---|---|
| Y1 | **Cacat yang ditemukan:** layar bayar QRIS sebelumnya menampilkan QR tiruan (`POS-MOCK|total=...`) yang tidak bisa dibayar siapa pun. Diganti gambar QRIS usaha; tanpa gambar, layar menampilkan petunjuk (QR tiruan dihapus) | Perlu diuji di HP: apakah pemindai bank membaca gambar yang diunggah |
| Y2 | QRIS statis tidak memuat nominal: pelanggan mengetik jumlah sendiri, dan kasir wajib mengecek dana masuk (alur konfirmasi manual yang sudah ada). Pembayaran tetap ditandai "QRIS manual (belum terverifikasi)" di laporan | Sesuai dokumen IMOGI (QRIS statis) |
| Y3 | Hanya peran dengan izin `pengaturan.kelola` (Owner) yang bisa mengunggah atau menghapus gambar; menghapus tidak digate paket. Satu gambar per usaha (bukan per outlet) | Perlu konfirmasi: per outlet? |
| Y4 | Hitung mundur 5 menit "kode kedaluwarsa" pada layar ini tidak bermakna untuk QRIS statis; belum dihapus | Perlu konfirmasi |
| Y5 | Gambar tidak diperiksa apakah benar QRIS (hanya format dan ukuran) | Susulan |

## Tambahan 2026-11-16 (pemisahan fitur per jenis usaha, Batch B tahap 1)

| # | Hal | Sementara |
|---|---|---|
| Z1 | Menjawab M3 sementara: fitur "tidak relevan" **disembunyikan** (sesuai dokumen IMOGI), bukan hanya ditandai. Tabel dampak per jenis usaha ada di `docs/pemisahan_per_jenis_usaha.md` | Perlu konfirmasi lead: disembunyikan atau cukup ditandai |
| Z2 | Penyembunyian hanya berlaku untuk kontrol yang dibungkus `FiturTerkunci`. Fitur tanpa klasifikasi, atau tanpa kontrol berfitur (mis. layar penuh yang dibuka lewat rute), tidak berubah | Perlu dicek kontrol mana lagi yang harus ikut disembunyikan |
| Z3 | Data lama menandai Kafe `dp_kasbon` tidak relevan, padahal DP hutang bisa dipakai kafe langganan; dan Restoran `nomor_antrean` tidak relevan padahal restoran cepat saji memakainya | Perlu konfirmasi: koreksi matriks IMOGI atau ikuti apa adanya |
| Z4 | Server hanya menyembunyikan di UI; server tetap menerima transaksi yang memakai fitur itu (push offline tidak boleh ditolak) | Sesuai prinsip offline-first |

## Tambahan 2026-11-16 (bawaan pengaturan per jenis usaha, Batch B tahap 2)

| # | Hal | Sementara |
|---|---|---|
| Z5 | Toko baru mendapat pesan penutup struk "Terima kasih, selamat menikmati!" dan pajak PB1 10% (ditambahkan di atas harga) untuk Kafe, Restoran, Katering, Roti, Minuman, Kios/Food Court. Bahan Segar/Beku tidak diberi PB1 | Mengikuti panduan IMOGI; perlu konfirmasi lead untuk FRZ dan besaran 10%. Pemilik bisa mematikan lewat saklar "Usaha kena pajak" |
| Z6 | Struk ringkas dan nomor antrean TIDAK dinyalakan otomatis walau panduan menyarankannya, karena keduanya terkunci paket (Pro) dan nilainya akan tersisa tanpa fitur setelah trial | Perlu keputusan lead: nyalakan selama trial atau tetap manual |
| Z7 | Bawaan hanya untuk toko yang mendaftar sesudah ini; toko lama tidak diubah. Modal awal shift Rp 300.000 dan tiket dapur otomatis belum dibuat | Susulan |

## Tambahan 2026-11-16 (peran bawaan kru, Batch B tahap 3)

| # | Hal | Sementara |
|---|---|---|
| Z8 | Peran sistem baru "Barista & Dapur" (hanya `transaksi.buat`) dan "Gudang" (`stok.kelola`, `pembelian.kelola`), migrasi 0028. Daftar 18 hak akses IMOGI belum dicocokkan: izin kini 15 kode dan tidak ada izin khusus seperti lihat margin, status pesanan, atau pengeluaran | Perlu daftar 18 hak akses dan matriks peran dari lead sebelum diperluas |
| Z9 | Peran ini global (semua jenis usaha), belum dipasang otomatis hanya untuk jenis usaha tertentu. Peran sistem baru ikut sync pull ke HP, tampil di pilihan peran karyawan | Perlu konfirmasi |

## Tambahan 2026-11-16 (pengingat kedaluwarsa, IMOGI no. 50)

| # | Hal | Sementara |
|---|---|---|
| AA1 | Batch kedaluwarsa hanya PENGINGAT: penjualan belum mengurangi `qty_sisa` batch (FIFO) dan batch belum otomatis dibuat dari pembelian | Perlu keputusan lead: apakah FIFO per batch dibutuhkan |
| AA2 | Pencatatan dan penghapusan batch butuh koneksi (lewat API); hasilnya sampai ke HP lewat sync. Tidak ada antrean offline untuk batch | Perlu konfirmasi: apakah harus bisa dicatat offline |
| AA3 | Pengingat hanya berupa penanda di daftar (Sudah lewat, Segera); belum ada pemberitahuan terjadwal atau lencana di menu | Susulan |
| AA4 | Pilihan produk di formulir batch diambil dari produk yang punya baris stok di outlet | Perlu dicek untuk produk tanpa lacak stok |

## Tambahan 2026-11-16 (tiket dapur per stasiun, IMOGI no. 35)

| # | Hal | Sementara |
|---|---|---|
| AB1 | Satu pesanan mencetak satu tiket per stasiun, berurutan lewat SATU printer yang terhubung ke HP. Kolom alamat printer per stasiun sudah ada di server tetapi belum dipakai | Perlu keputusan lead: printer terpisah per stasiun (Bar dan Dapur) atau cukup satu printer. Tidak bisa diuji tanpa perangkat |
| AB2 | Stasiun terikat ke outlet, sedangkan kategori terikat ke toko. Kategori yang ditautkan ke stasiun outlet A dan dipakai di outlet B akan mencetak sebagai tiket umum di B | Perlu konfirmasi bila usaha multi-outlet memakai stasiun berbeda |
| AB3 | Membuat, mengubah, dan menghapus stasiun butuh koneksi dan izin pengaturan.kelola (menu Lainnya). Menautkan kategori digerbang fitur tiket_dapur | Sama seperti batch kedaluwarsa (AA2) |
| AB4 | Menghapus stasiun melepas semua kategori yang memakainya (kembali ke tiket umum) | Sementara |

## Tambahan 2026-11-17 (penerapan otomatis promo ulang tahun, IMOGI no. 56)

| # | Hal | Sementara |
|---|---|---|
| AC1 | Memilih pelanggan yang berulang tahun hari ini di keranjang otomatis memasang promo ulang tahun pertama yang aktif, hanya bila kasir belum memilih promo lain. Kasir bisa mengganti atau melepasnya | Perlu konfirmasi: otomatis atau tetap manual |
| AC2 | Penerapan otomatis hanya terjadi saat memilih pelanggan; membuka kembali pesanan tersimpan tidak memasangnya lagi | Susulan |
| AC3 | Server belum memeriksa ulang tanggal lahir saat checkout (transaksi offline tidak boleh ditolak) | Sementara |
| AD1 | Ganti outlet (no. 87): watermark sync hanya satu untuk semua outlet, jadi saat berpindah outlet watermark direset ke awal (tarik penuh). Sementara; alternatif watermark per outlet bila datanya besar | Sementara |
| AD2 | Ganti outlet: sementara pindah DITOLAK bila ada shift terbuka di outlet sekarang (tutup shift dulu); transaksi belum terkirim tetap dikirim ke outlet asalnya. Perlu konfirmasi lead apakah aturan ini diinginkan | Sementara |
| AD3 | Ganti outlet hanya mengubah outlet aktif di HP; perangkat tetap terdaftar di outlet saat pairing (`perangkat.outlet_id`), server tidak memakainya untuk membatasi | Sementara |
| AE1 | Jual per kemasan (no. 43): rancangan yang disetujui: stok tetap di satuan dasar; baris transaksi menyimpan jumlah KEMASAN dan harga per kemasan (hitungan uang tidak berubah); stok berkurang qty x isi. Kemasan memakai harga kemasan tetap: harga outlet dan harga grosir per satuan dasar tidak berlaku pada baris kemasan | Sementara |
| AE2 | Jual per kemasan: checkout online server menolak item kemasan (harga online dihitung dari harga dasar produk); kemasan hanya lewat aplikasi kasir (sinkron offline). Perlu keputusan bila ada klien lain yang membutuhkan | Sementara |
| AE3 | Jual per kemasan: laporan penjualan per produk menjumlah qty dalam satuan jual (dus dan pcs bercampur); belum dikonversi ke satuan dasar. Pembelian/penerimaan stok per kemasan belum ada | Sementara |
| AF1 | Laba rugi konsolidasi (no. 84): total toko = laba rugi seluruh toko (termasuk biaya yang dicatat tanpa outlet dan transaksi outlet yang sudah dinonaktifkan), bukan penjumlahan baris outlet; selisihnya ditampilkan sebagai "biaya tanpa outlet". Hanya Owner/Manajer. Rumus mengikuti laba rugi no. 69 (sementara, perlu validasi akuntan) | Sementara |
| AG1 | Kirim WA massal (no. 57): sementara TIDAK ada kirim otomatis; tiap pesan dibuka di WhatsApp dan dikirim kasir sendiri (tanpa biaya gateway, tidak menyerupai spam). Perlu keputusan lead: apakah butuh gateway WhatsApp Business (kirim otomatis), persetujuan/opt-out pelanggan, dan batas jumlah penerima | Menunggu lead |
| AH1 | Survei pelanggan (no. 59): sementara online-only (survei dan jawaban di server, tanpa sinkron offline); kasir mengisikan jawaban atas nama pelanggan dari menu Lainnya, belum otomatis muncul di struk/layar pelanggan/WhatsApp walau kolom `tampil_di` ada. Perlu keputusan lead: kapan survei ditawarkan (setelah bayar? lewat tautan WA?), apakah jawaban anonim, dan apakah perlu offline | Menunggu lead |
| AI1 | Settlement QRIS/e-wallet (no. 74): sementara pencatatan MANUAL (pemilik mengetik dana yang masuk rekening); belum ada impor mutasi/laporan settlement dari Xendit atau penyedia lain, dan hari penjualan memakai tanggal UTC. Perlu keputusan lead: sumber data settlement (API gateway atau berkas penyedia), jeda cair per metode, dan zona waktu laporan | Menunggu lead |
| AJ1 | Aset tetap (no. 83): sementara hanya metode garis lurus; penyusutan mulai di bulan perolehan (bulan penuh), bulan terakhir menyerap sisa pembulatan, nilai buku berhenti di nilai residu. Angka aset bisa diubah (penyusutan dihitung ulang) dan ikut terkunci tutup buku; belum ada jurnal penyusutan, pelepasan/penjualan aset, atau saldo menurun. Perlu keputusan akuntan/lead: kebijakan awal penyusutan (bulan perolehan vs bulan berikutnya), metode lain, dan pencatatan jurnal | Menunggu lead |
| AK1 | Anggaran (no. 82): sementara anggaran per kategori biaya per bulan untuk seluruh toko (bukan per outlet); proyeksi akhir bulan LINEAR (realisasi / hari berjalan x jumlah hari) dan "selisih kasar" = proyeksi penjualan - proyeksi biaya, BUKAN laporan arus kas akuntansi (belum memuat piutang/utang/jadwal bayar). Ambang "hampir habis" 80%. Perlu keputusan akuntan/lead: kerangka proyeksi arus kas, anggaran per outlet, dan ambang peringatan | Menunggu lead |
| AL1 | Ekspor akuntansi (no. 85): sementara CSV NETRAL ringkasan harian (kolom tanggal, jenis, rincian, jumlah); aplikasi tidak menebak kode akun dan belum membuat format impor khusus Jurnal.id/Accurate/Zahir atau jurnal debit-kredit. Hari memakai tanggal UTC. Perlu keputusan akuntan/lead: software tujuan prioritas, bagan akun baku, dan format impornya | Menunggu lead |
| AM1 | Tutup buku (no. 78): sementara hanya mengunci pengeluaran, settlement, dan anggaran (anggaran terkunci per bulan: bila tanggal tutup di tengah bulan, bulan itu terkunci); transaksi penjualan TIDAK dikunci karena kasir offline masih mengirim data lama; aset tetap SUDAH ikut dikunci (sejak perbaikan 2026-11-17). Hanya Owner yang boleh menutup/membuka; tanggal tutup tidak boleh di masa depan dan harus lebih baru dari penutupan sebelumnya. Belum ada jurnal penutup atau saldo awal. Perlu keputusan akuntan/lead: apakah penjualan lama juga dikunci (koreksi lewat jurnal), siapa selain Owner yang boleh membuka, dan perlakuan saldo awal | Menunggu lead |
| AN1 | Deposit pelanggan (no. 79): sementara BUKU MUTASI saja; pemakaian deposit dicatat kasir manual ("Pakai") dan BELUM menjadi metode bayar otomatis di kasir, sehingga transaksi penjualan tidak terhubung ke pengurangan saldo. Tidak ada jurnal pengakuan pendapatan, kedaluwarsa saldo, atau membership berjangka. Pakai dicek terhadap saldo tanpa kunci baris (dua kasir bersamaan bisa melewati saldo; risiko kecil, belum ditangani). Perlu keputusan lead/akuntan: integrasi ke pembayaran kasir (offline?), kebijakan kedaluwarsa, dan saat pengakuan pendapatan | Menunggu lead |
| AO1 | Pembatas paket varian dan tambahan (`product_options`, Starter, IMOGI): sejak 2026-11-18 seluruh route varian, grup-modifier, dan modifier ditolak 403 untuk paket Free, dan menu "Varian & tambahan" ikut terkunci di aplikasi. Mengikuti katalog IMOGI, bukan keputusan baru. Toko Free yang sudah punya varian tetap menyimpannya; yang terkunci hanya kelola | Sementara |
| AO2 | **Shift kasir (`cash_shift`) di katalog IMOGI mulai Starter, tetapi aplikasi mewajibkan shift terbuka untuk transaksi.** Bila dikunci untuk Free, toko Free tidak bisa berjualan. Tidak saya kunci. Perlu keputusan lead: apakah Free berjualan tanpa shift, atau shift tetap terbuka untuk semua paket | Menunggu lead |
| AO3 | Fitur berbayar yang belum ada penjaga paketnya dan butuh keputusan karena menyentuh alur inti: `kelola_pelanggan` (Starter; pelanggan dipakai di kasir), `scan_barcode` (Starter), `payables` (Professional; piutang dan hutang usaha). Belum diubah | Menunggu lead |
| AO4 | Selama masa trial toko mendapat paket tertinggi, jadi pembatasan paket hanya terlihat setelah trial habis. Perlu keputusan lead: apakah ini diinginkan untuk rilis, dan cara QA menguji paket Free | Menunggu lead |
| AO5 | **Selesai 2026-11-18 (D6):** tombol "Kirim WhatsApp" di struk kini membuka chat pelanggan transaksi itu bila pelanggan dipilih dan punya nomor; tanpa pelanggan atau nomor tetap memakai menu bagikan. Belum diuji di HP | Selesai, menunggu uji HP |
| AO6 | **Selesai 2026-11-18 (B4):** ganti akun (login atau logout) mengosongkan keranjang, pelanggan, promo, tipe pesanan, catatan, poin, persetujuan diskon, dan penanda draft pesanan. Pesanan yang SUDAH disimpan tidak terhapus. Belum diuji di HP | Selesai, menunggu uji HP |
| AO7 | **Selesai 2026-11-18:** lencana paket di kartu profil Lainnya sebelumnya tulisan tetap "Gratis" untuk semua toko. Kini membaca nama paket efektif dari cache sync (selama trial tampil paket tertinggi) dan disembunyikan bila belum pernah sync. Belum diuji di HP | Selesai, menunggu uji HP |
| AP1 | **Disampaikan pengguna 2026-11-19 (TASK-104):** semua fitur yang terdaftar di file IMOGI harus sampai ke Release 1. Belum ada konfirmasi tertulis dari lead; belum menandai TASK-104 selesai di Task Tracker. Akibatnya fitur yang di workbook berstatus Future Release (mis. FEAT-034, 035, 036, 038, 076, 077, 078, 080) kini masuk Release 1. Perlu dipastikan: "semua" berarti 87 fitur atau 64 fitur relevan F&B (23 fitur kendaraan, apotek, dan sejenisnya berstatus tidak relevan untuk F&B) | Menunggu konfirmasi cakupan |
| AP2 | **Disampaikan pengguna 2026-11-19 (TASK-105):** tanggal mulai proyek 4 November 2026. Belum diisi ke sel D3 di Project Timeline (berkas tracker sedang terbuka di Excel). Estimasi 9 minggu dari tanggal itu jatuh sekitar 6 Januari 2027; per 19 November sudah minggu ke-3 | Menunggu pengisian workbook |
| AP3 | TASK-103 (requirement resmi): menunggu penjelasan pengguna apakah file IMOGI (87 fitur, 4 paket) dianggap requirement resmi yang menggantikan Feature Inventory. Belum diganti | Menunggu pengguna |
| AP4 | **Disampaikan pengguna 2026-11-19, melengkapi AP1 dan AP3:** requirement memakai fitur IMOGI (menggantikan Feature Inventory lama), cakupan Release 1 = fitur IMOGI yang relevan untuk F&B (64 dari 87), fokus F&B dulu. 23 fitur tidak relevan F&B tetap disembunyikan. Workbook (Feature Inventory, Release Scope) belum diperbarui karena berkas sedang terbuka; ID FEAT, TASK, dan PIC baru tidak saya karang | Disampaikan pengguna, belum tertulis dari lead |
| AQ1 | **Dikerjakan 2026-11-19:** layar masuk disatukan. Kolom "Nomor HP atau email": angka = OTP WhatsApp untuk pemilik usaha, huruf atau '@' = akun Administrator (kata sandi, langsung ke dashboard admin). Tombol "Masuk sebagai Administrator" dihapus dari layar pemilihan akun dan layar OTP; admin di HP yang sudah dipasangkan masuk lewat "Lupa PIN kasir?". Rute `/admin/login` tetap ada tetapi tidak ditautkan. Belum diuji di HP | Selesai, menunggu uji HP |
| AQ2 | Pendaftaran pemilik usaha memakai standar sekarang: nomor HP + OTP WhatsApp, kasir memakai PIN di perangkat yang dipasangkan. Keputusan lead yang belum ada: apakah pemilik boleh daftar dengan email + kata sandi, penyedia OTP WhatsApp atau SMS sungguhan (sekarang mock) beserta biayanya, dan jalur pemulihan bila pemilik ganti nomor (email cadangan atau bantuan admin) | Menunggu lead |
| AQ3 | **Selesai 2026-11-19:** nama usaha di kartu profil Lainnya sebelumnya menempel dari usaha lama (profil hanya ditulis saat daftar, tidak dihapus saat keluar dari usaha). Kini ditulis dari jawaban server tiap masuk atau daftar dan dihapus saat keluar. HP yang sudah menyimpan nama lama perlu keluar dari usaha dan masuk lagi satu kali | Selesai, menunggu uji HP |
| AR1 | **Dibangun 2026-11-20, belum diuji printer sungguhan:** label produk untuk kemasan (F&B). Satu stiker per porsi (nomor antrean, nama produk, tambahan, catatan, urutan n/total, waktu, nama toko), hanya untuk item yang kategorinya masuk tiket dapur. Printer label dipilih terpisah dari printer struk di Lainnya > Printer struk (ukuran 40x30, 50x30, 50x40, 58x40 mm, cetak otomatis setelah bayar, cetak tes) dan tombol "Cetak label kemasan" di layar struk. Bahasa perintah TSPL 203 dpi (Xprinter/TSC/Gprinter). Pertanyaan: merek dan model printer label yang dipakai (bila bukan TSPL, perlu ZPL atau CPCL), ukuran stiker standar, dan apakah dipakai juga untuk nomor pesanan di tipe order tertentu | Menunggu uji printer & jawaban lead |
| AS1 | **Dibangun 2026-11-22, belum diuji di HP:** (a) kartu debit/kredit (IMOGI no. 13): kasir memilih Debit atau Kredit di layar bayar kartu (wajib bila metode "wajib referensi"), daftar mesin EDC memakai label tujuan metode kartu (di pengaturan berjudul "Mesin EDC"), laporan memisahkan baris "Kartu · Debit · EDC BCA"; jenis kartu tersimpan di payload pembayaran dan ikut sync tanpa migrasi. (b) tombol "Kembalikan ke rekomendasi" di Pengaturan outlet dan struk: mengisi form dengan nilai panduan IMOGI menurut jenis usaha (struk ringkas dan antrean menyala untuk kafe, roti, minuman, food court), baru tersimpan setelah Simpan; pilihan yang terkunci paket tidak diubah | **Kartu debit diuji di HP 2026-11-22 (satu transaksi uji, Rp20.790, struk STR1795362048729):** layar Konfirmasi Kartu menampilkan pilihan Debit/Kredit, nomor referensi, dan 4 digit akhir kartu (opsional, dengan peringatan jangan memasukkan nomor lengkap); dipilih Debit dan referensi `UJI-EDC-001`, 4 digit akhir dikosongkan; server mencatat metode `kartu`, `ref_gateway` UJI-EDC-001, `payload_gateway` `{"jenis_kartu": "debit"}`; Laporan HP menampilkan baris "Kartu · Debit". **Belum diuji di HP:** jenis Kredit, label mesin EDC (label tujuan), "wajib referensi" menolak bila kosong (hanya tes otomatis), refund transaksi kartu, dan struk cetak. Pengamatan: struk di layar tidak memuat baris metode bayar atau referensi |
| AS2 | **Daftar 18 hak akses IMOGI sudah didapat 2026-11-22** (Panduan-Menu-Pengaturan-IMOGI-POS.pdf hlm. 28-29). Pemetaan ke izin aplikasi: 9 sudah ada (jualan=transaksi.buat, diskon tanpa persetujuan=transaksi.diskon, data pelanggan, kelola produk, stok dan barang masuk, kelola karyawan, laporan penjualan, buka/tutup shift dan kas, pengaturan); 8 belum ada (jual bon/DP, menyetujui dengan PIN, status pesanan dan antrian, daftar bon, lihat harga beli dan margin, posting stok opname, catat pengeluaran, laba rugi pajak dan margin); 1 tidak relevan F&B (anggota, arisan, kegiatan). Layar "Peran dan hak akses" (buat dan ubah peran dengan daftar centang) belum ada sama sekali; server baru punya daftar peran. Peran bawaan Barista dan Dapur serta Gudang sudah ada (migrasi 0028) | **Tahap 1-2 selesai 2026-11-22 (tes otomatis lulus, belum diuji HP):** 8 izin baru ditambahkan (migrasi 0035, pemberian paritas ke peran yang ada). Ditegakkan: laba rugi, konsolidasi, rekap pajak, PPh = laporan.keuangan; pengeluaran = pengeluaran.catat; posting stok opname = stok.opname_posting; HPP dan margin di form produk dan Laporan disembunyikan tanpa produk.lihat_margin (hanya di tampilan aplikasi, server tetap mengirim datanya). Belum ditegakkan: bon.jual, bon.lihat, pesanan.status, persetujuan.pin (fitur terkait belum dipisah). Tahap 3 selesai 2026-11-22 (tes otomatis lulus, belum diuji HP): endpoint GET /izin, GET/POST/PATCH/DELETE /roles (buat/ubah/hapus peran digate fitur kelola_karyawan; peran bawaan terkunci; hanya izin yang dimiliki pelaku boleh diberikan; peran yang masih dipakai karyawan tidak bisa dihapus) dan layar Lainnya > Peran dan hak akses |
| AT1 | **Definisi "Penjualan bersih" (ditemukan SIT di HP 2026-11-22):** tab Laporan menampilkan "Penjualan bersih Rp20.790" (termasuk service Rp900 dan PB1 Rp1.890), sedangkan Lainnya > Laba rugi menampilkan "Penjualan bersih Rp18.000" (tanpa pajak dan service) untuk transaksi yang sama. Dokumen IMOGI (Panduan-Menu-Pengaturan-IMOGI-POS.pdf hlm. 29 dan dashboard HTML) hanya menyebut "Laporan penjualan: omzet, produk terlaris, tren, daftar transaksi" dan "Laba rugi, pajak & margin"; **tidak ada** definisi "penjualan bersih" atau "total penerimaan", dan tidak dijelaskan apakah omzet termasuk pajak dan service. Layar Riwayat dan Laba rugi juga belum mengurangi transaksi yang sudah direfund (Laba rugi sudah menyebut "refund belum diperhitungkan") | **Keputusan sementara dibangun 2026-11-22 atas persetujuan pemilik (tes otomatis lulus, belum diuji di HP); validasi lead/akuntan tetap perlu.** Tab Laporan di HP: "Penjualan bersih" = total dikurangi pajak, service, dan pembulatan (sama dengan Laba rugi); "Pajak & service" dan "Total penerimaan" di baris terpisah; jam ramai, grafik tren, dan pembanding periode memakai penjualan bersih. Refund penuh dan void tidak dihitung; refund sebagian dikurangkan proporsional dari nominal yang dicatat HP ini (tabel `refund` lokal, tidak ikut sync). Riwayat: label "Penjualan" diganti "Total penerimaan" (void dan refund penuh tidak dihitung). **Diuji di HP 2026-11-22 (Uji Kopi Susu x2 = Rp41.580, refund 1):** Laporan HP menampilkan penjualan bersih Rp36.000, pajak & service Rp5.580, total penerimaan Rp41.580, 2 transaksi (bersama 1 transaksi lama yang masih "Selesai"); Laba rugi (server) menampilkan penjualan Rp18.000, HPP Rp7.000, laba kotor Rp11.000, 1 transaksi, pajak Rp2.790. Server mencatat refund Rp20.790 dan status `refund_sebagian`. Ditemukan juga: tab Laporan tidak menghitung ulang setelah penjualan atau refund baru (hanya berubah bila periode diganti); diperbaiki dengan memantau perubahan transaksi (tes `laporan_segar_test.dart`, belum diulang di HP). **Server dikerjakan 2026-11-22 (tes backend lulus 628):** `/laporan/penjualan`, `/laporan/produk-terlaris`, dan `/laporan/laba-rugi` (termasuk konsolidasi) memasukkan transaksi `refund_sebagian` dan mengurangi refund-nya: penjualan bersih (tanpa pajak, service, pembulatan; field baru `pajak_service` dan `total_penerimaan`), produk terlaris per qty yang tersisa, dan HPP hanya dikurangi untuk barang yang dikembalikan ke stok. Sebelumnya refund sebagian hilang seluruhnya dari laporan server. **Belum dikerjakan:** (a) rekap pajak, PPh Final, ekspor akuntansi, dan laporan shift di server masih memakai transaksi `selesai` saja (refund sebagian tidak ikut, refund penuh benar tidak ikut); (b) refund yang dibuat di HP lain, atau sebelum perbaikan ini, tidak diketahui nominalnya oleh HP ini; (c) di HP, laba kotor, produk terlaris, tren, dan margin tidak dikurangi refund sebagian (butuh rincian item refund; id item di server berbeda dari id lokal, jadi perlu pemetaan). Akibatnya di HP angka ini bisa lebih besar daripada penjualan bersih (contoh uji: laba kotor Rp33.000 dan tren produk Rp54.000 sementara penjualan bersih Rp36.000); (d) rincian per metode bayar (HP dan server) belum dikurangi refund sebagian; (e) transaksi yang sudah direfund sebelum perbaikan status 2026-11-22 tetap berstatus "Selesai" di HP lama. Perlu validasi akuntan, terutama perlakuan service charge (pendapatan toko atau dibagi ke karyawan) |
| AT2 | **Refund tidak mengurangi kas seharusnya shift (ditemukan SIT di HP 2026-11-22; DIPERBAIKI di server 2026-11-22, tes backend lulus 634, kas shift nyata dihitung ulang Rp183.160 menjadi Rp120.790, TERBUKTI lewat tutup shift di HP 2026-11-22 22:55: shift ditutup di HP lalu Sync; payload HP hanya memuat `kas_aktual` (tanpa kas seharusnya dan selisih), dan server mencatat kas_seharusnya Rp120.790, kas_aktual Rp120.790, selisih Rp0):** `shift_service._sum_refund_tunai` menjumlah `Refund.total` dengan INNER JOIN ke `metode_bayar` lewat `Refund.metode_bayar_id`. Refund dari aplikasi memakai "Sama seperti transaksi asal", sehingga `metode_bayar_id` kosong dan refund itu tidak pernah terhitung. Bukti (fungsi asli dijalankan pada shift terbuka 2026-11-22): tunai masuk Rp83.160, total refund di shift Rp83.160 (4 refund), tetapi "refund tunai" = Rp0 dan kas seharusnya = Rp183.160. Seharusnya Rp120.790 (modal 100.000 + tunai 83.160 - refund atas 3 transaksi tunai 62.370; refund transaksi QRIS 20.790 tidak memengaruhi laci), jadi kas seharusnya terlalu besar Rp62.370 dan tutup shift akan menunjukkan selisih kurang palsu | **Perbaikan (keputusan sementara):** `_sum_refund_tunai` kini menjumlah `Refund.kas_dikembalikan` (uang yang benar-benar keluar; sebelumnya `total`, yang berlebihan untuk refund kasbon yang menutup sisa tagihan). Bila `metode_bayar_id` terisi: tunai hanya bila metode itu `masuk_laci`. Bila kosong: dikali porsi pembayaran tunai pada transaksi asal, jadi bayar campur dibagi proporsional dan refund transaksi QRIS/kartu tidak mengurangi laci. Refund yang sudah dihapus lunak tidak dihitung. Perlu keputusan lead: pembagian refund untuk bayar campur (proporsional dipakai sementara). Catatan: baris refund sebelum migrasi 0003 bernilai `kas_dikembalikan` 0, tetapi hanya shift terbuka yang dihitung ulang (shift tutup menyimpan nilai terkunci) |
| AT4 | **Form Tutup shift di HP meminta kasir mengetik "Kas seharusnya" sendiri (ditemukan SIT di HP 2026-11-22, belum diperbaiki):** `tutup_shift_form_page.dart` punya dua isian wajib, "Kas seharusnya (Rp)" dan "Kas aktual di laci (Rp)"; komentar kode menyebut "belum dihitung otomatis ... masih input manual". HP menghitung selisih dari angka ketikan itu ("Kas sesuai"/selisih di layar), sedangkan server menghitung ulang kas seharusnya saat sinkron dan mengabaikan angka HP (`sync_service._push_satu_shift`). Akibatnya kasir bisa melihat "Kas sesuai" di HP padahal selisih sebenarnya di server berbeda, dan kasir harus menghitung sendiri kas seharusnya. Server sudah punya angka yang benar (`GET /laporan/shift/{id}`, `hitung_kas_seharusnya`) | Perilaku sekarang dipertahankan. Usulan: isi otomatis "Kas seharusnya" di HP dari data lokal (modal + tunai + kas masuk - kas keluar - refund tunai) atau dari server bila online, dan tampilkan selisih dari angka itu. Perlu keputusan: perhitungan lokal harus mengikuti aturan server (porsi tunai pada bayar campur, refund tanpa metode) agar tidak berbeda |
| AT3 | **Refund yang diproses di shift berikutnya mengurangi shift lama (ditemukan 2026-11-22, belum diperbaiki):** server mendukung `shift_id` pada body refund (shift tempat uang keluar dari laci; kosong = shift transaksi asal), tetapi aplikasi tidak pernah mengirimnya (`refund_page.dart`). Akibatnya refund atas penjualan kemarin mengurangi kas shift kemarin (yang sudah tertutup dan terkunci), sedangkan uang keluar dari laci hari ini, sehingga kas shift hari ini terlalu besar. Dokumentasi perilaku ada di `backend/tests/test_shift_refund.py` | Aplikasi tetap tidak mengirim `shift_id`. Usulan: kirim id shift terbuka di HP saat refund. Risiko yang perlu diputuskan: server menolak `shift_id` yang belum ada atau tidak aktif di server, jadi bila shift baru belum tersinkron refund bisa gagal; pilihannya memaksa sinkron dulu seperti refund atas transaksi belum tersinkron, atau mengirim `shift_id` hanya bila shift tersebut sudah tersinkron |
