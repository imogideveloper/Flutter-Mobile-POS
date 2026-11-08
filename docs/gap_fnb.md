# Catatan Gap: POS untuk Bisnis F&B

Tanggal: 2026-11-06. Sasaran produk: kafe, kedai kopi, minuman, kios makanan.

> **Catatan 2026-11-08:** berkas ini memakai daftar Qasir dan sudah **digantikan oleh [gap_imogi.md](gap_imogi.md)** (acuan utama: dokumen IMOGI). Dipertahankan sebagai riwayat.
>
> Ringkasan terpadu (paket, backend, risiko rilis, keputusan lead) ada di [temuan_audit.md](temuan_audit.md). Berkas ini tetap menjadi rincian per fitur.

**Metode:** pembacaan kode (Flutter `lib/` dan backend `backend/app/`) dan pencarian pemakaian tiap kode fitur.
Belum ada yang dijalankan di HP. Status "ada" artinya kodenya ditemukan, bukan sudah lulus uji manual.

Legenda: ✅ ada di kode dan terhubung ke UI, 🟡 sebagian atau belum terhubung, ❌ tidak ada.

---

## A. Daftar fitur paket (32 kode fitur, sesuai gambar Qasir Pro)

Gambar menampilkan 35 baris (22 berikon centang hijau, 13 berikon silang merah) karena "Manage bundles" muncul dua kali, dan tiga item ekspor/unggah berada di satu kode `ekspor_impor`. Tabel di bawah memakai 34 baris (bundling ditulis sekali).

| # | Fitur | Kode | Status | Temuan |
|---|-------|------|--------|--------|
| 1 | Sistem POS | `pos` | ✅ | Kasir, keranjang, bayar, struk, riwayat, refund/void. |
| 2 | Cetak struk | `cetak_struk` | ✅ | ESC/POS lewat Bluetooth. |
| 3 | Scan produk | `scan_barcode` | ✅ | `barcode_scan_page.dart`, `findByBarcode`, dipakai di kasir. |
| 4 | Kelola stok | `kelola_stok` | ✅ | Halaman stok dan mutasi. |
| 5 | Kelola pelanggan | `kelola_pelanggan` | ✅ | CRUD, piutang, pelunasan. |
| 6 | Laporan penjualan | `laporan_dasar` | ✅ | Tab periode, batas hari per paket. |
| 7 | Pembayaran QRIS | `qris` | 🟡 | Halaman dan backend Xendit ada. Kunci Xendit kosong (backend 503), belum pernah diuji. |
| 8 | Bayar dengan utang | `kasbon` | ✅ | `bayar_kasbon_page.dart`. |
| 9 | Tren penjualan | `tren_penjualan` | 🟡 | Laporan hanya punya ringkasan, produk terlaris, metode bayar, dan jam ramai. Tidak ada grafik tren harian (`fl_chart` terpasang tapi tidak dipakai). |
| 10 | Multi-outlet | `multi_outlet` | 🟡 | Backend `outlet.py` ada. Di Flutter tidak ada UI ganti outlet. `outletId` masih placeholder dan nama "Outlet Pusat" tertulis langsung di `lainnya_page.dart`. |
| 11 | Bahan baku dan resep | `resep` | ✅ | `_ResepSection` di form produk. Pemotongan stok bahan terjadi di backend. |
| 12 | Ekspor produk | `ekspor_impor` | ❌ | Tidak ada kode ekspor di Flutter maupun backend. |
| 13 | Unggah produk via template | `ekspor_impor` | ❌ | Sama. |
| 14 | Unggah pelanggan via template | `ekspor_impor` | ❌ | Sama. |
| 15 | Kelola diskon | `diskon` | ✅ | Halaman promo. |
| 16 | Pajak per produk | `pajak_per_produk` | ✅ | Dipakai di kalkulator dan form produk. |
| 17 | Tipe pesanan | `tipe_order` | ✅ | CRUD tipe pesanan dan meja, pemilih tipe di keranjang. |
| 18 | Kelola karyawan | `kelola_karyawan` | ✅ | Halaman pengguna. |
| 19 | Poin loyalitas | `poin_loyalitas` | ✅ | Poin didapat dihitung di backend. Penukaran ada di keranjang. |
| 20 | Diskon member | `diskon_member` | ✅ | Level member dan kalkulator. |
| 21 | Survei pelanggan | `survei` | ❌ | Hanya 4 tabel lokal. Tidak ada UI, tidak ada endpoint backend. |
| 22 | Absensi karyawan | `absensi` | ❌ | Hanya 1 tabel lokal. Tidak ada UI, tidak ada endpoint backend. |
| 23 | Struk ringkas | `struk_ringkas` | ✅ | Pengaturan outlet dan penyusun struk. |
| 24 | Cetak tiket dapur | `tiket_dapur` | ❌ | Tidak ada fungsi cetak tiket dapur di Flutter. Yang ada hanya tabel dan endpoint backend `/dapur/pesanan`. |
| 25 | Catatan tambahan di struk | `catatan_struk` | 🟡 | Catatan pesanan tercetak di struk. Kode `catatan_struk` tidak dipakai untuk membatasi fitur, jadi aturan paketnya tidak berlaku. |
| 26 | Service fee per tipe pesanan | `service_per_tipe_order` | ✅ | Kalkulator dan form tipe pesanan. |
| 27 | Status pesanan | `status_pesanan` | ❌ | Kolom `statusPesanan` ada di tabel transaksi, tetapi tidak ada kode yang mengisi atau menampilkannya. |
| 28 | DP untuk kasbon | `dp_kasbon` | ✅ | `bayar_kasbon_page.dart`. |
| 29 | Nomor antrean | `nomor_antrean` | 🟡 | Ada saklar di pengaturan struk, cetak di struk, dan endpoint backend. Tidak ditemukan kode Flutter yang meminta atau membuat nomornya, jadi nomor tidak pernah terisi. |
| 30 | Label metode pembayaran | `label_pembayaran` | ✅ | `pengaturan_metode_bayar_page.dart`. |
| 31 | Logo usaha di struk | `logo_struk` | ✅ | Pengaturan outlet dan konversi ESC/POS. |
| 32 | Kelola bundling | `bundling` | ✅ | `_BundlingSection` di form produk. |
| 33 | Pengingat kedaluwarsa | `pengingat_kedaluwarsa` | ❌ | Backend punya kolom `lacak_kedaluwarsa` dan tanggal kedaluwarsa per batch stok. Tidak ada UI, pengingat, atau job. |
| 34 | Harga grosir | `harga_grosir` | ✅ | Kalkulator dan form produk. |

**Ringkasan:** 21 ✅, 5 🟡, 6 ❌ (dari 32 kode fitur).

---

## B. Gap alur khas F&B (di luar daftar paket)

Diurutkan dari yang paling menghambat pemakaian di kafe.

| Prioritas | Gap | Bukti | Dampak |
|-----------|-----|-------|--------|
| **Kritis** | **Varian dan modifier tidak bisa dipilih di kasir.** | `ItemKeranjang` hanya menyimpan `produkId`, tanpa varian atau modifier. Tabel `produk_varian`, `grup_modifier`, `modifier` ada. Form produk menyatakan "varian dan modifier sengaja belum ada" dan tidak ada CRUD grup modifier. | Ukuran, level gula, es, dan topping tidak bisa dijual. Ini kebutuhan inti kafe dan kedai minuman. |
| **Kritis** | **Tiket dapur dan bar tidak bisa dicetak atau ditampilkan.** | Lihat fitur #24. Tidak ada layar dapur dan tidak ada UI stasiun. | Barista atau dapur tidak menerima pesanan dari kasir. |
| **Tinggi** | **Meja tidak bisa dipilih saat transaksi.** | Ada CRUD meja, tetapi tidak ada `mejaId` di keranjang atau di pesanan tersimpan. | Dine-in tidak bisa dikaitkan ke meja. Open bill per meja tidak mungkin. |
| **Tinggi** | **Catatan per item tidak ada di UI.** | Kolom `catatan` di `item_transaksi` ada. Keranjang hanya punya catatan seluruh pesanan. | Permintaan seperti "tanpa gula" atau "pedas" tidak bisa dicatat per menu. |
| **Tinggi** | **Nomor antrean dan status pesanan tidak jalan.** | Lihat fitur #27 dan #29. | Pelanggan take-away tidak punya nomor panggil. Kasir tidak bisa menandai "siap". |
| **Sedang** | **Pisah bill dan gabung bill, pindah meja.** | Tidak ditemukan di kode. | Sering dibutuhkan di resto dine-in. Untuk kedai kopi kecil bisa menyusul. |
| **Sedang** | **Laporan F&B.** | Laporan hanya penjualan bersih, jam ramai, metode bayar, produk terlaris. Tidak ada penjualan per kategori atau tipe pesanan, dan tidak ada pemakaian bahan baku atau HPP. | Pemilik tidak bisa menilai margin menu. |
| **Sedang** | **Stok bahan baku di perangkat belum diverifikasi.** | Pemotongan resep terlihat di backend. Belum dicek apakah offline di Flutter ikut memotong atau menunggu sync. | Stok bahan bisa meleset saat offline. Perlu uji manual. |
| **Rendah** | **Tandai menu habis (sold out) dan tip.** | Belum diperiksa, tidak ditemukan saat pencarian cepat. | Nyaman dimiliki, bukan penghalang rilis. |

---

## C. Gap lintas bisnis (sudah tercatat sebelumnya, tetap berlaku)

Lihat `playstore-prep-audit-findings` di memory: sync tidak otomatis, build release belum siap (izin INTERNET, base URL, signing), OTP lemah, dan JWT secret bawaan.
Sync otomatis paling berisiko untuk kafe ramai karena data transaksi hanya aman setelah sinkron.

---

## D. Urutan pengerjaan yang disarankan untuk target F&B

1. **Varian dan modifier:** CRUD grup modifier di form produk, lalu pemilih di kasir, lalu ikut ke keranjang, struk, dan sync.
2. **Pemilih meja dan catatan per item** di keranjang, termasuk di pesanan tersimpan.
3. **Tiket dapur:** cetak per stasiun (bar/dapur) saat bayar atau saat simpan pesanan, lalu layar dapur dan status pesanan.
4. **Nomor antrean:** hubungkan ke checkout.
5. **Sync otomatis** (item audit #1).
6. **Laporan F&B:** per kategori dan tipe pesanan, lalu bahan baku terpakai.
7. **QRIS:** isi kunci Xendit mode test dan uji sampai transaksi terkonfirmasi.
8. **Ekspor/unggah, survei, absensi, kedaluwarsa, tren grafik, UI multi-outlet:** setelah inti F&B stabil. Survei, absensi, dan kedaluwarsa bukan inti F&B.
