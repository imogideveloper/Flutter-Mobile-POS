# Temuan Audit Terpadu: POS F&B

Tanggal: 2026-11-08. Menggabungkan `docs/gap_fnb.md`, audit kesiapan rilis, dan pemeriksaan paket serta backend.

**Metode dan batas.** Semua temuan berasal dari pembacaan kode (Flutter `lib/`, backend `backend/app/`, migrasi `backend/alembic/`) dan nama berkas tes.
Tidak ada yang dijalankan di HP dan tes backend tidak dijalankan. Status "ada" berarti kodenya ditemukan, bukan sudah lulus uji.
Daftar Qasir Pro hanya referensi dari lead, bukan requirement resmi.

Legenda: ✅ lengkap, 🟡 sebagian, ❌ belum ada.

---

## 1. Ringkasan satu halaman

| Area | Kesimpulan |
|---|---|
| Arah produk | Fokus F&B (kafe, kedai kopi, kios makanan). Perlu validasi lead. |
| Paket | Sudah ada 3 paket (Gratis, Pro, Bisnis) dengan batas jumlah, 32 kode fitur, dan batas riwayat laporan. Harga di migrasi adalah "harga contoh". |
| Kelengkapan fitur | Dari 32 kode fitur: 21 ✅, 5 🟡, 6 ❌. Tidak ada fitur di daftar Qasir yang tanpa padanan di katalog. |
| Alur F&B | Dua gap kritis: varian/modifier dan tiket dapur. Tiga gap tinggi: meja, catatan per item, nomor antrean/status pesanan. |
| Backend | Kuat dari sisi tes dan isolasi data. Lemah di empat hal rilis: sync otomatis, build release, OTP, JWT secret. |
| Perlu keputusan lead | Urutan fitur, paket untuk fitur F&B baru, harga, pemakaian katalog 32 fitur. Lihat bagian 9. |

---

## 2. Pengaturan paket

Sumber: migrasi `0001_initial_schema.py` baris 1124 sampai 1166 dan `0002_batas_laporan_dasar.py`. Isinya sama dengan `backend/app/core/seed.py` (data uji).

### 2.1 Batas per paket

| | Gratis (setara Basic) | Pro | Bisnis |
|---|---|---|---|
| Harga per bulan | Rp 0 | Rp 59.000 | Rp 99.000 |
| Harga per tahun | Rp 0 | Rp 590.000 | Rp 990.000 |
| Maks outlet | 1 | tanpa batas | tanpa batas |
| Maks pengguna | 2 | 10 | tanpa batas |
| Maks produk | 100 | tanpa batas | tanpa batas |
| Riwayat laporan | 30 hari | 365 hari | tanpa batas |
| Jumlah fitur terbuka | 6 | 20 | 32 |

Harga di migrasi ditulis "Harga contoh, silakan sesuaikan". Belum tentu keputusan bisnis.

### 2.2 Cara paket bekerja

- Tabel `fitur` menyimpan 32 fitur. Tiap fitur punya `tingkat`, yaitu paket minimum yang membukanya (0 Gratis, 1 Pro, 2 Bisnis).
- Tabel `paket_fitur` diisi otomatis oleh migrasi: tiap paket membuka semua fitur dengan tingkat sama atau lebih rendah.
- Kolom `batas` di `paket_fitur` baru dipakai satu fitur: `laporan_dasar` (30/365/tanpa batas hari). Strukturnya bisa dipakai fitur lain, tetapi belum ada.
- Kuota jumlah ditegakkan di backend: pengguna (`routers/pengguna.py`), produk (`routers/produk.py`), outlet (`services/outlet_service.py`). Error-nya `kuota_habis`.
- Langganan punya status `aktif`/`trial`. Pekerjaan terjadwal `tandai_langganan_kedaluwarsa` menandai langganan lewat tanggal sebagai `kedaluwarsa`, dan toko turun ke fitur Gratis. Data toko tidak dihapus.
- Aplikasi Flutter menyimpan status gating lokal (`feature_gate_provider.dart`) dan menampilkan lembar "fitur terkunci" (`fitur_terkunci_sheet.dart`). Server tetap menolak 403 sebagai penjaga akhir.

### 2.3 Fitur per paket dan status implementasi

**Gratis: 6 fitur, semua ✅**

| Kode | Fitur | Status |
|---|---|---|
| `pos` | Kasir (POS) | ✅ |
| `cetak_struk` | Cetak struk | ✅ |
| `scan_barcode` | Scan produk | ✅ |
| `kelola_stok` | Kelola stok | ✅ |
| `kelola_pelanggan` | Kelola pelanggan | ✅ |
| `laporan_dasar` | Laporan penjualan (30 hari) | ✅ |

**Tambahan di Pro: 14 fitur (8 ✅, 3 🟡, 3 ❌)**

| Kode | Fitur | Status | Catatan |
|---|---|---|---|
| `kasbon` | Bayar dengan utang | ✅ | |
| `resep` | Bahan baku dan resep | ✅ | |
| `diskon` | Kelola diskon | ✅ | |
| `pajak_per_produk` | Pajak per produk | ✅ | Tidak ada gerbang di backend; penegakan di HP |
| `tipe_order` | Tipe pesanan | ✅ | |
| `kelola_karyawan` | Kelola karyawan | ✅ | CRUD dasar tidak digate; dibatasi kuota pengguna |
| `poin_loyalitas` | Poin loyalitas | ✅ | |
| `diskon_member` | Diskon member | ✅ | |
| `qris` | Pembayaran QRIS | 🟡 | Kunci Xendit kosong, belum diuji |
| `tren_penjualan` | Tren penjualan | 🟡 | Tanpa grafik |
| `multi_outlet` | Multi-outlet | 🟡 | Tanpa UI ganti outlet |
| `ekspor_impor` | Ekspor dan unggah template | ❌ | Tidak ada kode |
| `survei` | Survei pelanggan | ❌ | Hanya tabel lokal |
| `absensi` | Absensi karyawan | ❌ | Hanya tabel lokal |

**Tambahan di Bisnis: 12 fitur (7 ✅, 2 🟡, 3 ❌)**

| Kode | Fitur | Status | Catatan |
|---|---|---|---|
| `struk_ringkas` | Struk ringkas | ✅ | |
| `service_per_tipe_order` | Service fee per tipe pesanan | ✅ | |
| `dp_kasbon` | DP untuk kasbon | ✅ | |
| `label_pembayaran` | Label metode pembayaran | ✅ | |
| `logo_struk` | Logo usaha di struk | ✅ | |
| `bundling` | Kelola bundling | ✅ | |
| `harga_grosir` | Harga grosir | ✅ | Penegakan di HP, bukan di endpoint checkout |
| `catatan_struk` | Catatan tambahan di struk | 🟡 | Catatan tercetak; gerbang paket ada di checkout |
| `nomor_antrean` | Nomor antrean | 🟡 | Endpoint ada dan digate; HP tidak meminta nomor |
| `tiket_dapur` | Cetak tiket dapur | ❌ | Digate di checkout, tetapi tidak ada fungsi cetak |
| `status_pesanan` | Status pesanan | ❌ | Kolom ada, tidak ada yang mengisi |
| `pengingat_kedaluwarsa` | Pengingat kedaluwarsa | ❌ | `batch_stok` tidak dipakai backend |

### 2.4 Catatan desain paket (untuk lead)

- Fitur F&B inti (tiket dapur, nomor antrean, status pesanan) ada di paket tertinggi, Rp 99.000.
- Varian/modifier, pilih meja, catatan per item, pisah bill, dan laporan F&B belum punya kode fitur, jadi belum punya paket.
- Multi-outlet tercatat sebagai fitur Pro, tetapi Gratis dibatasi 1 outlet, dan Pro tanpa batas. Konsisten, tetapi biaya per outlet ("biaya per outlet" di nama fitur) belum terlihat di tabel harga.
- Pembagian paket hanya satu angka per fitur (`tingkat`), jadi murah untuk diubah.

---

## 3. Perbandingan dengan daftar Qasir Pro

Gambar (dikirim ulang 2026-11-08) berjudul "Run your business like a pro with Qasir Pro!". Isinya 35 baris: 22 berikon hijau (termasuk di Qasir Pro) dan 13 berikon merah (tidak termasuk, artinya ada di paket yang lebih tinggi).

- **Cakupan katalog sama.** Semua baris punya kode di katalog 32 fitur. Gambar punya 35 baris karena "Manage bundles" muncul dua kali dan tiga item ekspor/unggah (produk, unggah produk, unggah pelanggan) dipetakan ke satu kode `ekspor_impor`.
- **Pembagian paket sama persis dengan kode.**
  - 22 baris hijau = 20 kode fitur = fitur tingkat Gratis dan Pro di aplikasi.
  - 13 baris merah = 12 kode fitur = fitur tingkat Bisnis di aplikasi (concise receipt, tiket dapur, catatan struk, service fee per tipe pesanan, status pesanan, DP kasbon, nomor antrean, label pembayaran, logo struk, bundling, pengingat kedaluwarsa, harga grosir).
  - Gambar tidak membedakan Gratis dan Pro, jadi batas 6 fitur Gratis adalah rancangan aplikasi ini, bukan hasil menyalin Qasir.
- **Catatan Qasir yang cocok dengan kode:** "Sales reports according to subscription period" sesuai batas riwayat laporan per paket (30/365/tanpa batas hari). "Multi-outlet (additional fees apply)" sesuai nama fitur `multi_outlet` ("biaya per outlet").
- **Gap-nya implementasi**, bukan katalog atau pembagian paket: 6 ❌ dan 5 🟡 (lihat 2.3).

---

## 4. Alur bisnis F&B

Diurutkan dari yang paling menghambat pemakaian di kafe.

| Prioritas | Gap | Bukti |
|---|---|---|
| **Kritis** | Varian dan modifier belum bisa dipilih di kasir | `ItemKeranjang` hanya menyimpan `produkId`. Tabel `produk_varian`, `grup_modifier`, `modifier` ada. Tidak ada CRUD grup modifier. |
| **Kritis** | Tiket dapur/bar belum bisa dicetak atau ditampilkan | Tidak ada fungsi cetak. Tidak ada layar dapur. |
| **Tinggi** | Meja belum bisa dipilih saat transaksi | CRUD meja ada, tetapi tidak ada `mejaId` di keranjang atau pesanan tersimpan. |
| **Tinggi** | Catatan per item belum ada di UI | Kolom `catatan` di `item_transaksi` ada. |
| **Tinggi** | Nomor antrean dan status pesanan belum jalan | `CheckoutIn` tidak punya field `nomor_antrean`. `statusPesanan` tidak pernah diisi. |
| **Sedang** | Pisah/gabung bill, pindah meja | Tidak ditemukan di kode. |
| **Sedang** | Laporan F&B (kategori, tipe pesanan, HPP) | Laporan hanya ringkasan, produk terlaris, metode bayar, jam ramai. |
| **Sedang** | Stok bahan baku saat offline belum diverifikasi | Pemotongan resep terlihat di backend; perilaku offline di HP belum dicek. |
| **Rendah** | Menu habis (sold out) dan tip | Tidak ditemukan; belum diperiksa mendalam. |

---

## 5. Temuan backend

**Kekuatan**
- Ada 47 berkas tes di `backend/tests/` (belum dijalankan di sesi ini). Cakupannya mencakup checkout, refund/void, sync, kasbon, langganan, gating fitur, isolasi antar toko (`test_isolasi_toko`, `test_multitenant_isolation`, `test_isolasi_semua_endpoint`), dan pembayaran Xendit.
- Paket ditegakkan di server: `fitur_map.py` mendaftar endpoint yang digate, dan `test_gating_fitur.py` menguji bahwa toko Gratis ditolak 403.
- Checkout online menghitung ulang harga di server (`harga_satuan` dari klien diabaikan). Harga disusun lewat kalkulator bersama Dart dan Python, dengan fixture lintas bahasa.
- Kuota pengguna, produk, dan outlet ditegakkan di backend.

**Kelemahan dan risiko**
- **Sync offline mempercayai harga dari HP.** Untuk transaksi offline yang di-sync, server menyimpan `harga_satuan` dan `subtotal_klien` dari klien (`checkout_service.py` sekitar baris 626 sampai 644). Klien yang diubah bisa mengirim harga sembarang. Untuk kasir internal risikonya rendah, tetapi layak dicatat.
- **Komentar `fitur_map.py` kedaluwarsa.** Baris `qris` menulis "Belum ada endpoint gateway QRIS", padahal ada `routers/payment_xendit.py` dan dua berkas tes Xendit. Baris `nomor_antrean` dan `tiket_dapur` juga perlu disegarkan.
- **Tidak ditemukan pembatasan laju (rate limiting) di `backend/app`.** Ini memperparah risiko OTP.
- **`pajak_per_produk` tidak digate di backend.** Dicatat di `fitur_map.py`: tidak ada endpoint CRUD dan tidak dipakai di checkout server. Penegakan hanya di HP.
- **Harga grosir juga hanya ditegakkan di HP.** Server menerima harga yang sudah dibakukan HP.
- **Alur bayar langganan belum jelas.** Dokumentasi kode menyebut permintaan upgrade "tanpa pembayaran di dalam app". Ada router `admin_langganan.py` (persetujuan manual) dan Xendit untuk pembayaran langganan, tetapi alur ujungnya belum diuji.

---

## 6. Risiko rilis (ditunda atas keputusan pengguna)

| # | Temuan | Dampak | Perbaikan |
|---|---|---|---|
| 1 | Sync tidak otomatis. `SyncRepository.jalankan()` hanya manual; `workmanager` terpasang tetapi tidak dipakai. | Transaksi hilang jika HP rusak sebelum sync. Paling berisiko untuk kafe ramai. | Sync latar belakang saat online. |
| 2 | Build release belum siap: tidak ada izin INTERNET di manifest utama; base URL `http://localhost:8001`; ditandatangani debug key. | Aplikasi tidak bisa terhubung di HP lain dan tidak diterima Play Store. | Izin, URL produksi, keystore rilis. |
| 3 | OTP memakai `random.randint`, tanpa batas percobaan, dan OTP masih dicetak ke log. | OTP bisa ditebak. | Pakai `secrets`, batas percobaan, penyedia SMS/WhatsApp. |
| 4 | `DEFAULT_JWT_SECRET` tertanam di `config.py`; validasi hanya aktif jika `ENVIRONMENT=production`. | Token bisa dipalsukan bila deploy lupa set environment. | Secret acak dari environment; tolak start tanpa secret. |

---

## 7. Temuan lain

- **Status perbaikan (2026-11-08):** kode BUG-010 (sync 422), BUG-011 (metode bayar), dan BUG-013 (void ganda) sudah diperbaiki dan punya tes otomatis, tetapi **belum diuji ulang di HP**, jadi di Excel statusnya Ready for Retest, bukan Closed. BUG-012 dan lainnya belum diperbaiki.
- **Tiga bug yang dialami langsung di HP (2026-11-08), semuanya terkonfirmasi dari kode dan data:**
  1. **Sync gagal 422 (BUG-010, Critical).** `transaksiBelumSync()` ikut mengirim pesanan tersimpan (draft). Untuk draft, `metode_bayar_id` diisi placeholder `metode-tunai-default` yang bukan UUID, sehingga seluruh `POST /sync/push` ditolak (`uuid_parsing`). Reproduksi dengan model `SyncPushIn` di backend memberi hasil yang sama, dan nilai UUID yang valid lolos. Akibatnya 3 transaksi selesai tertahan di HP dan pull ikut dilewati.
  2. **Metode bayar Tunai hilang dan tidak bisa diaktifkan (BUG-011, Critical).** Server mencatat Tunai aktif, tetapi database HP mencatat nonaktif. Saat switch diubah, server berhasil diubah lalu penyimpanan lokal gagal (`NOT NULL constraint failed: metode_bayar.toko_id`, diuji pada salinan database HP) karena `upsertMetodeBayar` hanya memberi `id` dan `aktif`. Sync tidak bisa memulihkannya karena push gagal (bug 1). Sebab awal Tunai menjadi nonaktif belum diketahui.
  3. **Pengaturan outlet tidak bisa disimpan di paket Gratis (BUG-012, Major).** `tampil_logo` bernilai true di server (default), form mengirim semua nilai, dan server menolak karena paket Gratis tidak punya fitur logo. Perubahan lain di form ikut gagal.
- **Tombol "Masuk dengan PIN karyawan" tidak berfungsi** (dialami langsung di HP OPPO Reno8, 2026-11-08). Tombol di layar OTP memanggil `onSelesai`, tetapi `AuthGatePage` (baris 46) mengisinya dengan `() {}`, sehingga tidak terjadi apa pun. Di instalasi baru belum ada akun karyawan, jadi tombol ini juga belum berguna. Pilihan perbaikan: sembunyikan selama perangkat belum dipasangkan, atau sambungkan ke layar pilih pengguna + PIN. Belum diperbaiki. Dicatat sebagai BUG-009 dan TC-052.
- **UI multi-outlet:** nama "Outlet Pusat" tertulis langsung di `lainnya_page.dart`; `outletId` masih placeholder.
- **Perubahan lokal belum di-commit** (bukan dari audit ini): `backend/docker-compose.yml` (port 8001), `lib/core/network/api_config.dart`, file `.g.dart` dan `pubspec.lock`. Port 8001 dipakai karena 8000 bentrok dengan Frappe; akses HP lewat `adb reverse tcp:8001 tcp:8001`.
- **Dokumen yang sudah ada:** `docs/aturan_harga.md`, `docs/uji_manual_printer.md`.
- **Dokumentasi QA:** 3 berkas Excel di `docs/dokumentasi-qa/` (tracker, QA & testing, UAT & release). Berisi data DUMMY seri 9xx yang tidak dihitung di ringkasan.

---

## 7b. Hasil uji manual di HP (2026-11-08, OPPO Reno8, paket Gratis)

Ringkasan di Excel: dari 56 test case, 22 sudah ada hasil (3 Pass, 9 Fail, 10 Blocked). Kolom "Penyebab" berasal dari pembacaan kode, bukan uji ulang.

| # | Temuan pengguna | Jenis | Penyebab / keterangan | Catatan di Excel |
|---|---|---|---|---|
| 1 | Tidak bisa masuk dengan PIN karyawan | Bug | Tombol di layar OTP memanggil fungsi kosong (`auth_gate_page.dart` baris 46). PIN karyawan di database HP ada (bcrypt), jadi login PIN di layar pilih pengguna kemungkinan bisa. | BUG-009 |
| 2 | Format struk tidak bisa disimpan di paket Gratis (pesan logo usaha paket Bisnis) | Bug | `tampil_logo` bernilai true di server (default), form mengirim semua nilai, server menolak karena paket Gratis. | BUG-012 |
| 3 | Printer Bluetooth belum diuji (tidak ada perangkat) | Terblokir | Tidak ada printer. | TC-018 sampai 020 Blocked |
| 4 | Kasir hanya bisa menambah item; qty tidak bisa diketik | Fitur belum ada | Pengurangan lewat +/- di keranjang. | Fitur "qty manual" |
| 5 | Tombol promo di keranjang belum berfungsi | Kemungkinan paket | Membuat promo butuh paket Pro, jadi daftar kosong tanpa petunjuk. Tampilan layar belum diperiksa. | BUG-016, TC-029 Blocked |
| 6 | Item bisa melebihi stok; opsi tidak bisa dimatikan | Bug | `izinkan_stok_minus` bernilai true di server dan tidak bisa disimpan karena BUG-012. | TC-009 Fail |
| 7 | Stok hanya mencatat stok tersedia dan mutasi terakhir | Fitur belum ada | Tabel `mutasi_stok` menyimpan semua mutasi, tetapi layar hanya menampilkan yang terakhir. | Fitur "riwayat mutasi stok" |
| 8 | Transaksi tidak berhasil sync | Bug | Pesanan tersimpan ikut dikirim dengan ID placeholder, seluruh push ditolak 422. | BUG-010 |
| 9 | Kasbon belum diuji (paket Gratis) | Terblokir | Kasbon terkunci di paket Gratis. | TC-015 sampai 017 Blocked |
| 10 | QRIS tidak ada di pembayaran campur | Fitur belum ada | QRIS sengaja dikecualikan di `bayar_page.dart`. | Fitur "QRIS di split" |
| 11 | Refund menampilkan "transaksi tidak ditemukan" | Bug | Refund selalu online; transaksi belum tersync tidak ada di server. | BUG-014 |
| 12 | Void/Refund tetap tampil setelah void; void kedua menambah stok lagi | Bug serius | `voidTransaksi()` tidak memeriksa status; detail tidak dimuat ulang. | BUG-013 |
| 13 | Makanan/minuman sudah dibuat tetapi void: stok manual | Alur bisnis | Void selalu mengembalikan stok. | Fitur "void dengan pilihan stok" |
| 14 | Metode pembayaran tidak tercatat di riwayat | Bug | `labelMetodeBayar()` hanya memetakan dua ID placeholder; ID asli berbentuk UUID. | BUG-015 |
| 15 | Tipe pesanan dine in/take away/delivery ada di paket Pro | Sesuai kode | `tipe_order` bertingkat Pro. | Sudah ada di Paket & Fitur |
| 16 | Kategori produk tidak muncul di kasir | Fitur belum ada | Kategori hanya dipakai di kelola produk; kasir tidak punya filter. | Fitur "filter kategori di kasir" |
| 17 | Resep belum dicoba | Belum diuji | Butuh paket Pro. | TC-026 Not Tested |
| 18 | Update data setelah sync lambat | Observasi | Belum diukur; periksa ulang setelah BUG-010 diperbaiki. | BUG-017 |
| 19 | Pilih meja, catatan per item, tiket dapur, nomor antrean, status pesanan belum ada | Fitur belum ada | Sesuai daftar gap F&B. | TC-021 Fail; TC-043 sampai 045 Blocked |

---

## 7c. Arahan lead (2026-11-08) dan dokumen IMOGI

> **Alur pesanan kafe (2026-11-08):** nomor antrian, tiket dapur, status pesanan, dan varian & tambahan produk sudah dikerjakan di kode dan lulus tes otomatis (Flutter 256, backend 425), tetapi **belum diuji di HP dan printer**. Varian & tambahan: halaman kelola di menu Lainnya, pemilih di kasir (termasuk scan), masuk keranjang, riwayat, struk, tiket dapur, dan sync. Sisa: estimasi selesai dan WhatsApp saat siap, tahap Diantar, pengaturan awalan nomor antrian, kategori masuk tiket dapur, cetak ulang tiket dari riwayat. Detail per fitur ada di `docs/gap_imogi.md`.

> **Fondasi selesai di kode (2026-11-08):** katalog backend kini 4 paket IMOGI (Free, Starter, Professional, Enterprise) dengan 87 fitur (migrasi 0010, terpasang di database lokal), dan jenis usaha memakai 7 kode F&B IMOGI (CAF, RES, CAT, BRD, FRZ, BEV, STL). Ringkasan di [gap_imogi.md](gap_imogi.md). Belum diuji di HP dan belum di-commit.
>
> **Pembaruan 2026-11-08:** dokumen IMOGI (`IMOGI POS Menu & Fitur.html` dan `Panduan-Menu-Pengaturan-IMOGI-POS.pdf`) ditetapkan sebagai acuan utama, dan aplikasi difokuskan ke modul Makanan & Minuman (7 jenis usaha). Perbandingan lengkap 87 fitur ada di [gap_imogi.md](gap_imogi.md). Bagian 2, 3, dan 4 dokumen ini memakai katalog lama (Qasir) dan hanya berlaku sebagai catatan riwayat.

**Arahan lead (dikutip dari catatan balasan, diringkas):**
- Semua stopper uji disebabkan oleh tier paket.
- Semua tier dibuka dulu tanpa pembatasan. Tier baru berlaku setelah usia akun mencapai batas (awal 4 bulan), dan durasinya harus dapat dikonfigurasi.
- Konfigurasi usia akun lewat **dashboard admin Imogi** (kemungkinan versi desktop). Isi dashboard masih akan ditelusuri lead. Fitur yang disebut: konfigurasi usia akun, jumlah pengguna yang mengunduh, jumlah pengguna registrasi, konfigurasi paket/tier.
- Ada dua dashboard: **dashboard owner bisnis** dan **dashboard admin Imogi**.

**Dampak teknis (dari pembacaan kode):**
- Titik perubahan ada satu: `paket_efektif()` di `backend/app/services/fitur_service.py`. Semua gating fitur, kuota, dan data paket yang dikirim ke HP lewat fungsi ini. Toko yang usianya di bawah batas dapat dikembalikan sebagai paket tertinggi.
- Usia akun dapat dihitung dari `created_at` toko (kolom sudah ada).
- Konfigurasi durasi belum punya tempat penyimpanan: tidak ada tabel pengaturan platform di database.
- Dashboard admin belum ada. Backend baru punya satu endpoint admin (`POST /admin/langganan/aktivasi`) dengan kunci API statis, dan kunci itu kosong sehingga endpoint menolak semua permintaan. Dashboard dengan login pengguna butuh autentikasi admin tersendiri.
- Jumlah registrasi dapat dihitung dari tabel toko dan pengguna. **Jumlah unduhan tidak ada di backend**; sumbernya Google Play Console atau pencatatan instalasi.
- Dashboard owner juga belum ada, dan bentuknya (web, desktop, atau di aplikasi) belum jelas.
- Keputusan ini membuat bug yang terblokir tier (BUG-012, kasbon, promo, resep) tidak lagi menjadi penghalang uji, tetapi tidak memperbaiki bug-nya sendiri.

**Keputusan lanjutan dari pengguna (2026-11-08):**
- Setelah batas usia akun, tidak ada penguncian mendadak. Aplikasi menampilkan status "Free trial paket Pro/Bisnis selama 4 bulan, batas berakhir: tanggal akhir", dan notifikasi dikirim menjelang berakhir. Waktu notifikasi ditulis "7 minggu"; perlu dikonfirmasi apakah maksudnya 7 minggu atau 7 hari sebelum berakhir.
- Usia akun dihitung dari tanggal toko mendaftar.
- Toko uji milik pengguna ikut dihitung dengan aturan yang sama.

**Pertanyaan yang masih terbuka:** paket mana yang jadi acuan (3 paket aplikasi atau 4 paket IMOGI), dan apakah/bagaimana aplikasi terhubung ke dashboard. Spesifikasi awal aplikasi (`PROMPT_Senior_Mobile_Dev_POS (1).md`) merencanakan dashboard owner berupa web Next.js yang membaca PostgreSQL yang sama; dashboard itu belum ada di repo ini.

**Implementasi masa trial (2026-11-08, selesai di kode, belum diuji di HP):**
- Tabel baru `pengaturan_platform` (migrasi 0009) berisi `usia_akun_bulan` = 4 dan `trial_notifikasi_hari` = 7. Nilai 0 mematikan trial.
- `paket_efektif()` mengembalikan paket dengan `urutan` tertinggi selama usia akun (dari `toko.created_at`) belum mencapai batas, tanpa bergantung nama paket. Kuota pengguna, produk, dan outlet ikut terbuka.
- `GET /langganan/saya` kini mengirim `trial_aktif`, `trial_berakhir`, `trial_hari_tersisa`, `paket_efektif_nama`. Halaman paket di aplikasi menampilkan "Free trial paket X selama N bulan. Batas berakhir: tanggal", dan berubah menjadi peringatan saat sisa 7 hari atau kurang.
- Job harian (07:30) membuat satu baris notifikasi per toko saat sisa 7 hari atau kurang. **Belum ada push notification**: backend belum punya endpoint notifikasi dan aplikasi belum membacanya, jadi yang terlihat pengguna baru banner di halaman paket.
- Durasi dapat diubah lewat `PUT /admin/pengaturan-platform` (kunci API admin). Dashboard admin nanti memakai endpoint yang sama.
- Toko uji milik pengguna ikut dihitung: trial 4 Nov 2026 sampai 4 Mar 2027, paket efektif Bisnis (diverifikasi langsung di database lokal).
- Tes: 12 tes backend baru, 3 tes widget baru; seluruh 386 tes backend lulus.

**Ketidaksesuaian yang perlu ditanyakan ke lead.** Dokumen *IMOGI POS Menu & Fitur* (diperbarui 5 Nov 2026, sumber `src/app/data/features.ts`) memuat **4 paket (Free, Starter, Professional, Enterprise)**, 11 modul, 87 fitur, dan 43 jenis usaha. Aplikasi saat ini memakai **3 paket (Gratis, Pro, Bisnis)** dan **32 fitur** hasil salinan daftar Qasir. Contoh perbedaannya untuk Kafe & Kedai Kopi menurut dokumen IMOGI:

| Fitur | Paket di dokumen IMOGI | Di aplikasi sekarang |
|---|---|---|
| Varian dan tambahan produk (ukuran, level, topping) | Starter, inti untuk kafe | Belum ada, tanpa kode fitur |
| Tipe pesanan | Starter | Pro |
| Split payment | Starter | Tidak dikunci paket |
| Bahan baku dan resep | Professional | Pro |
| Poin loyalti, diskon member, survei, absensi | Professional | Pro |
| Cetak tiket dapur, nomor antrian, struk ringkas, status pesanan, logo struk | Enterprise | Bisnis |
| Kelola paket (bundle), label jenis pembayaran, biaya layanan per tipe pesanan | Enterprise | Bisnis |
| Akuntansi (jurnal, buku besar, payroll, dll.) | Professional/Enterprise | Tidak ada |

Dokumen IMOGI kemungkinan adalah sumber kebenaran produk, bukan daftar Qasir. Itu berarti analisis gap dan sheet Paket & Fitur sebaiknya diselaraskan ulang setelah lead memutuskan. Saya belum membaca ulang seluruh 87 fitur dokumen itu untuk perbandingan lengkap.

---

## 8. Yang belum diverifikasi

- Seluruh perilaku di HP (alur kasir, printer, offline, sync, gating UI).
- Hasil tes backend (belum dijalankan).
- Alur pembayaran langganan sampai ujung.
- Apakah aplikasi sudah menyembunyikan atau mengunci semua menu fitur berbayar.

---

## 9. Keputusan yang dibutuhkan dari lead

1. Validasi fokus F&B dan pemakaian katalog 32 fitur (dipakai semua, atau subset).
2. Paket minimum untuk fitur F&B baru: varian/modifier, pilih meja, catatan per item, pisah bill, laporan F&B.
3. Apakah harga contoh (Rp 59.000 dan Rp 99.000) dipakai, dan apakah tiket dapur boleh di paket Bisnis saja.
4. Urutan pengerjaan fitur yang belum ada (usulan: varian/modifier, meja dan catatan item, tiket dapur, nomor antrean, sync otomatis, laporan F&B, QRIS).
5. Kapan empat risiko rilis dikerjakan, dan siapa menyiapkan keystore rilis serta alamat server produksi.
6. Pemakaian template Excel, penyetuju UAT, dan validasi estimasi 9 minggu.
