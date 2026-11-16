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
