# Gap Fitur: Aplikasi vs Daftar IMOGI (acuan utama)

Tanggal: 2026-11-08. Menggantikan `docs/gap_fnb.md` sebagai acuan utama. Daftar Qasir Pro tidak dipakai lagi.

**Sumber acuan (moment of truth):**
- `IMOGI POS Menu & Fitur.html` (diperbarui 5 Nov 2026): 4 paket, 11 modul, 87 fitur, 43 jenis usaha, dan kebutuhan fitur (inti/opsional/tidak relevan) per jenis usaha.
- `Panduan-Menu-Pengaturan-IMOGI-POS.pdf` (versi November 2026, 41 halaman): isi menu Pengaturan, nilai bawaan per jenis usaha, dan paket minimum tiap bagian.

**Metode dan batas.** Status aplikasi berasal dari pembacaan kode dan data uji manual 2026-11-08, bukan uji menyeluruh di HP. Beberapa baris ditandai "belum diperiksa" pada kolom temuan. Fokus aplikasi: modul **Makanan & Minuman** (7 jenis usaha, lihat bagian 3).

---

## 1. Ringkasan

| | Jumlah |
|---|---|
| Fitur di daftar IMOGI | 87 |
| Relevan untuk Makanan & Minuman (inti atau opsional untuk minimal 1 dari 7 jenis usaha) | 64 |
| Tidak relevan untuk Makanan & Minuman (disembunyikan) | 23 |
| ✅ Lengkap | 15 |
| 🟡 Sebagian | 24 |
| ❌ Belum ada | 25 |
| Fitur inti untuk Kafe & Kedai Kopi | 46 (✅ 11, 🟡 18, ❌ 17) |

**Temuan utama:**
1. **Katalog paket sudah diselaraskan (fondasi selesai, migrasi 0010).** Backend kini memakai 4 paket IMOGI (Free, Starter, Professional, Enterprise) dan 87 fitur; sebelumnya 3 paket dan 32 fitur hasil salinan Qasir. Harga dan kuota paket masih **harga contoh** karena dokumen IMOGI tidak memuatnya. Fitur baru belum menggerbang apa pun sampai diimplementasikan.
2. **Hampir separuh fitur relevan F&B belum ada**, terutama modul Akuntansi (laba rugi, PPN/PB1, PPh Final, jurnal, payroll, dll.) dan keuangan dasar (pengeluaran).
3. **Alur pesanan kafe sudah terbangun sebagian (2026-11-08):** varian dan tambahan produk (ukuran, level gula, topping), tiket dapur, status pesanan, dan nomor antrian sudah ada di kode dan lulus tes otomatis, tetapi **belum diuji di HP dan printer**. Yang tersisa: estimasi selesai, pesan WhatsApp saat siap, tahap Diantar, pengaturan awalan nomor antrian.
4. **Menu Pengaturan versi IMOGI belum ada.** IMOGI punya 11 tab pengaturan dengan bawaan otomatis per jenis usaha, simpan otomatis, dan tombol "Kembalikan ke rekomendasi". Aplikasi hanya punya pengaturan terpisah-pisah (lihat bagian 6).
5. **Beberapa gap dari analisis lama tidak ada di daftar IMOGI**: pilih meja saat transaksi, catatan per item, pisah/gabung bill, layar dapur (KDS), menu habis (sold out), dan tip. Kata "meja" tidak muncul di kedua dokumen. Perlu konfirmasi lead apakah tetap dikerjakan.
6. **Mode bisnis sudah diganti (fondasi selesai)** dari pilihan umum (retail, fnb, jasa, laundry, fashion) menjadi 7 jenis usaha Makanan & Minuman dengan kode IMOGI. Bawaan pengaturan per jenis usaha belum dibuat.

---

## 2. Paket IMOGI

| Paket IMOGI | Fitur relevan F&B yang pertama terbuka di paket ini |
|---|---|
| Free | 11 |
| Starter | 15 |
| Professional | 16 |
| Enterprise | 22 |

Paket lebih tinggi mencakup semua fitur paket di bawahnya. Multi-Outlet adalah add-on berbayar di paket Professional ke atas (di katalog backend dihitung sebagai bagian Professional, jadi Professional berisi 64 fitur; dokumen IMOGI menyebut 63 tanpa add-on). Akun demo mendapat semua fitur. Cara upgrade menurut panduan: pilih paket, tekan "Ajukan upgrade", tim IMOGI menghubungi untuk pembayaran, paket aktif setelah dibayar.

---

## 3. Jenis usaha Makanan & Minuman (mode bisnis)

Tujuh jenis usaha di kelompok ini: **Kafe & Kedai Kopi, Restoran, Katering, Roti/Kue & Camilan, Bahan Segar & Makanan Beku, Minuman, Kios & Food Court.**

**Status fondasi:** pilihan saat daftar toko, penyimpanan di backend (`toko.jenis_usaha`), dan validasi sudah memakai 7 kode IMOGI (CAF, RES, CAT, BRD, FRZ, BEV, STL). Nilai lama `fnb` dipetakan ke Kafe & Kedai Kopi. Tabel `fitur_kebutuhan` di database menyimpan kebutuhan fitur (inti/opsional/na) per jenis usaha. Yang belum: nilai bawaan dan visibilitas pengaturan per jenis usaha. Menurut panduan IMOGI, jenis usaha menentukan:
- nilai bawaan pengaturan (pajak, biaya layanan, struk, antrian, tiket dapur, stok, dll.),
- bagian pengaturan yang tampil (utama, opsional, atau disembunyikan),
- nama tab (mis. "Stok & Resep" untuk makanan dan minuman),
- peran bawaan kru (mis. "Barista & Dapur").

---

## 4. Gap fitur relevan F&B

Diurutkan: inti untuk Kafe & Kedai Kopi lebih dulu. ❌ = belum ada, 🟡 = sebagian.

| No | Modul | Fitur IMOGI | Paket IMOGI | Kebutuhan F&B (7 jenis) | Status | Temuan |
|---|---|---|---|---|---|---|
| 3 | Kasir | Kelola diskon | Free | 7 inti, 0 opsional, Kafe: Inti | 🟡 | Promo dan diskon ada. Belum ada pengaturan tombol cepat diskon manual, izin diskon item oleh kasir, dan batas diskon dengan PIN owner. |
| 10 | Pembayaran | Pembayaran QRIS | Starter | 7 inti, 0 opsional, Kafe: Inti | 🟡 | QRIS dinamis Xendit belum teruji (kunci kosong). Imogi memakai QRIS statis dari gambar yang diunggah usaha; pengaturan unggah gambar QRIS belum ditemukan. |
| 36 | Produk | Kelola produk, kategori & harga | Free | 7 inti, 0 opsional, Kafe: Inti | 🟡 | CRUD produk, kategori, dan harga ada. Kasir tidak punya tab kategori (Imogi: tab kasir mengikuti urutan kategori). |
| 37 | Produk | Harga beli & margin produk | Free | 7 inti, 0 opsional, Kafe: Inti | 🟡 | HPP dan margin tampil di form produk. Belum ada penanda margin di bawah batas (bawaan 50% untuk F&B) dan hak akses lihat harga beli. |
| 38 | Produk | Upload produk via template | Starter | 7 inti, 0 opsional, Kafe: Inti | ❌ | Tidak ada kode unggah template. |
| 65 | Laporan | Tren penjualan | Starter | 7 inti, 0 opsional, Kafe: Inti | 🟡 | Tanpa grafik tren. |
| 67 | Akuntansi | Catat pengeluaran & biaya operasional | Starter | 7 inti, 0 opsional, Kafe: Inti | ❌ | Tidak ada pencatatan pengeluaran dan kategori pengeluaran (F&B: belanja bahan [HPP], gas LPG, kemasan). |
| 69 | Akuntansi | Laporan laba rugi | Professional | 7 inti, 0 opsional, Kafe: Inti | ❌ | Hanya laba kotor di ringkasan laporan; tidak ada laporan laba rugi. |
| 70 | Akuntansi | Rekap pajak PPh Final UMKM (0,5%) | Professional | 7 inti, 0 opsional, Kafe: Inti | ❌ | Tidak ada rekap PPh Final. |
| 72 | Akuntansi | HPP & margin per produk/layanan | Professional | 7 inti, 0 opsional, Kafe: Inti | 🟡 | HPP per item tersimpan dan margin tampil di form produk. Belum ada laporan HPP dan margin. |
| 61 | Karyawan | Kelola karyawan | Starter | 6 inti, 1 opsional, Kafe: Inti | 🟡 | CRUD pengguna dan peran ada. Daftar hak akses Imogi (jualan, bon/DP, status pesanan, lihat margin, pengeluaran, dst.) dan peran bawaan Barista & Dapur belum dicocokkan. |
| 74 | Akuntansi | Settlement & rekonsiliasi QRIS/e-wallet | Professional | 6 inti, 1 opsional, Kafe: Inti | ❌ | Tidak ada settlement atau rekonsiliasi QRIS dan e-wallet. |
| 13 | Pembayaran | Pembayaran kartu debit/kredit (EDC) | Free | 5 inti, 2 opsional, Kafe: Inti | 🟡 | Metode kartu ada. Belum ada pengaturan jenis kartu, daftar mesin EDC, dan kewajiban isi no. referensi/4 digit. |
| 15 | Pembayaran | Split payment (bayar campur) | Starter | 4 inti, 3 opsional, Kafe: Inti | 🟡 | Split payment ada, tetapi QRIS dikecualikan. Belum digerbang paket di kode. |
| 35 | Dapur | Cetak tiket pesanan dapur | Enterprise | 4 inti, 2 opsional, Kafe: Inti | 🟡 | SELESAI sebagian (2026-11-08): tiket dapur tanpa harga (nomor antrian, waktu, menu dan jumlah) dicetak otomatis setelah pembayaran dan bisa dicetak ulang dari halaman sukses; lulus tes susunan tiket. KEMAJUAN 2026-11-10: kategori bisa dikeluarkan dari tiket (saklar "Masuk tiket dapur" di form kategori, migrasi 0013) dan tiket bisa dicetak ulang dari detail riwayat. Belum ada tombol auto-print terpisah, tiket per stasiun, dan uji di printer (belum ada perangkat). |
| 42 | Produk | Varian & tambahan produk (ukuran, level, topping) | Starter | 4 inti, 2 opsional, Kafe: Inti | 🟡 | SELESAI sebagian (2026-11-08): halaman Varian & tambahan (menu Lainnya) untuk membuat grup (ukuran, level gula, topping) beserta opsi berharga dan aturan wajib/maksimal pilih, memasangnya ke banyak produk; katalog turun ke HP lewat sync. Kasir membuka pemilih saat produk punya tambahan (juga lewat scan), harga ikut dihitung, baris keranjang terpisah per pilihan, tersimpan di pesanan tersimpan dan riwayat, tampil di struk dan tiket dapur, terkirim saat sync. Lulus 22 tes Flutter dan tes backend. Belum diuji di HP. Belum ada: urutan opsi yang bisa digeser, tambahan khusus per produk (hanya grup bersama), izin kelola terpisah di sisi aplikasi. |
| 18 | Pembayaran | Label jenis pembayaran | Enterprise | 3 inti, 4 opsional, Kafe: Inti | 🟡 | Aplikasi: ubah nama/urutan metode bayar. Imogi: label tujuan (GoPay, OVO, ShopeePay, bank) untuk rekonsiliasi. Konsepnya berbeda. |
| 26 | Dapur | Status pesanan | Enterprise | 3 inti, 3 opsional, Kafe: Inti | 🟡 | SELESAI sebagian (2026-11-08): status awal Baru dibuat saat checkout, halaman Status Pesanan (menu Lainnya) memajukan tahap Baru, Diproses, Siap, Selesai (katering: Dipesan, Dimasak, Siap kirim, Dikirim, Selesai), tersimpan offline dan dikirim lewat sync (migrasi 0011). KEMAJUAN 2026-11-10: pesanan bertipe antar otomatis memuat tahap Diantar. Belum ada estimasi selesai, pesan WhatsApp saat siap, dan uji di HP. |
| 34 | Dapur | Nomor antrian | Enterprise | 3 inti, 1 opsional, Kafe: Inti | 🟡 | SELESAI sebagian (2026-11-08): HP membuat nomor A-001 sendiri saat offline (per hari, outlet, perangkat), tersimpan di transaksi, tampil di struk dan halaman sukses, dikirim lewat sync. KEMAJUAN 2026-11-10: awalan dan angka awal bisa diatur per outlet di Pengaturan struk (migrasi 0012). Belum ada panggilan suara, layar antrian, dan nama di layar antrian. Belum diuji di HP. |
| 62 | Karyawan | Absensi karyawan | Professional | 3 inti, 4 opsional, Kafe: Inti | ❌ | Hanya tabel lokal. |
| 63 | Karyawan | Jadwal shift mingguan & cuti | Professional | 3 inti, 4 opsional, Kafe: Inti | ❌ | Tidak ada jadwal shift mingguan dan cuti. |
| 76 | Akuntansi | Penggajian (payroll) & kasbon karyawan | Enterprise | 3 inti, 4 opsional, Kafe: Inti | ❌ | Tidak ada penggajian dan kasbon karyawan. |
| 80 | Akuntansi | Chart of Accounts & jurnal umum | Enterprise | 3 inti, 4 opsional, Kafe: Inti | ❌ | Tidak ada chart of accounts dan jurnal umum. |
| 81 | Akuntansi | Buku besar, neraca & arus kas | Enterprise | 3 inti, 4 opsional, Kafe: Inti | ❌ | Tidak ada buku besar, neraca, dan arus kas. |
| 82 | Akuntansi | Anggaran & proyeksi arus kas | Enterprise | 3 inti, 3 opsional, Kafe: Inti | ❌ | Tidak ada anggaran dan proyeksi arus kas. |
| 85 | Akuntansi | Ekspor ke software akuntansi (Jurnal, Accurate, Zahir) | Enterprise | 3 inti, 4 opsional, Kafe: Inti | ❌ | Tidak ada ekspor ke software akuntansi. |
| 4 | Kasir | Pajak per produk | Starter | 2 inti, 5 opsional, Kafe: Inti | 🟡 | Pajak per produk ada. Belum ada pengaturan status pajak usaha (kena/tidak kena), nama pajak (PB1/PPN), dan cara hitung (termasuk/ditambahkan) dengan bawaan per jenis usaha. |
| 6 | Kasir | Biaya layanan per tipe pesanan | Enterprise | 2 inti, 3 opsional, Kafe: Inti | 🟡 | Service fee per tipe pesanan ada. Bawaan 5% makan di tempat untuk kafe dan restoran belum otomatis dari jenis usaha. |
| 24 | Struk | Logo usaha di struk | Enterprise | 2 inti, 5 opsional, Kafe: Inti | 🟡 | Logo ada (unggah). Imogi juga menyediakan gaya logo siap pakai (lingkaran, cincin, inisial) dan tanpa logo. BUG-012 menghalangi simpan pengaturan di paket Gratis. |
| 59 | Pelanggan | Survei pelanggan | Professional | 2 inti, 5 opsional, Kafe: Inti | ❌ | Hanya tabel lokal. |
| 73 | Akuntansi | Rekap pajak PPN & PB1 | Professional | 2 inti, 5 opsional, Kafe: Inti | ❌ | Tidak ada rekap PPN dan PB1. |
| 83 | Akuntansi | Aset tetap & penyusutan | Enterprise | 2 inti, 4 opsional, Kafe: Inti | ❌ | Tidak ada aset tetap dan penyusutan. |
| 84 | Akuntansi | Laporan keuangan konsolidasi multi-outlet | Enterprise | 2 inti, 5 opsional, Kafe: Inti | ❌ | Tidak ada laporan keuangan konsolidasi. |
| 87 | Outlet | Multi-Outlet | Professional | 2 inti, 5 opsional, Kafe: Inti | 🟡 | Backend ada; di aplikasi tidak ada UI ganti outlet. |
| 56 | Pelanggan | Promo ulang tahun pelanggan | Professional | 1 inti, 5 opsional, Kafe: Inti | ❌ | tanggal_lahir ada di backend tetapi tidak disimpan di HP; tidak ada promo ulang tahun. |
| 71 | Akuntansi | Piutang & hutang usaha (AR/AP) | Professional | 5 inti, 2 opsional, Kafe: Opsional | 🟡 | Piutang pelanggan (kasbon) ada. Hutang usaha ke supplier belum dicocokkan (backend punya modul pembelian). |
| 16 | Pembayaran | Pembayaran hutang (bon) | Starter | 3 inti, 4 opsional, Kafe: Opsional | 🟡 | Kasbon, jatuh tempo, dan pelunasan ada. Limit bon per pelanggan dan penahanan bon baru belum ditemukan. |
| 49 | Stok | Kelola stok produk | Free | 3 inti, 4 opsional, Kafe: Opsional | 🟡 | Stok dan mutasi ada, tetapi layar hanya menampilkan mutasi terakhir. Pengaturan saat stok habis terblokir BUG-012. |
| 50 | Stok | Pengingat kedaluwarsa produk | Enterprise | 2 inti, 5 opsional, Kafe: Opsional | ❌ | Backend punya kolom/batch kedaluwarsa; tanpa UI atau job. |
| 14 | Pembayaran | Pembayaran transfer bank | Free | 1 inti, 6 opsional, Kafe: Opsional | 🟡 | Metode transfer ada. Belum ada daftar rekening bank (bank, nomor, atas nama). |
| 39 | Produk | Ekspor produk | Starter | 1 inti, 6 opsional, Kafe: Opsional | ❌ | Tidak ada kode ekspor. |
| 43 | Produk | Jual per kemasan (pcs, dus, pak) | Starter | 1 inti, 1 opsional | ❌ | Tidak ada konsep jual per kemasan (pcs, dus, pak). |
| 79 | Akuntansi | Pendapatan diterima di muka (deposit/membership) | Enterprise | 1 inti, 3 opsional, Kafe: Opsional | ❌ | Tidak ada pendapatan diterima di muka. |
| 25 | Struk | Catatan tambahan di struk | Enterprise | 0 inti, 7 opsional, Kafe: Opsional | 🟡 | Catatan pesanan tercetak. Teks catatan tambahan toko di bawah struk (maks. 300 karakter) belum ditemukan. |
| 27 | Dapur | Terima order, bayar belakangan (nota order) | Free | 0 inti, 3 opsional, Kafe: Opsional | 🟡 | Open bill dan kasbon ada. Tombol Terima Order dan pilihan kapan pelanggan membayar belum ada. |
| 53 | Pelanggan | Upload pelanggan via template | Professional | 0 inti, 6 opsional, Kafe: Opsional | ❌ | Tidak ada unggah pelanggan lewat template. |
| 57 | Pelanggan | Kirim WA ke banyak pelanggan | Professional | 0 inti, 5 opsional, Kafe: Opsional | ❌ | Hanya kirim struk lewat WhatsApp; belum ada kirim pesan massal ke pelanggan. |
| 77 | Akuntansi | BPJS & PPh 21 di penggajian | Enterprise | 0 inti, 7 opsional, Kafe: Opsional | ❌ | Tidak ada BPJS dan PPh 21. |
| 78 | Akuntansi | Tutup buku akhir tahun | Enterprise | 0 inti, 7 opsional, Kafe: Opsional | ❌ | Tidak ada tutup buku akhir tahun. |

---

## 5. Fitur yang sudah lengkap (relevan F&B)

| No | Fitur IMOGI | Paket IMOGI | Kode fitur di aplikasi | Catatan |
|---|---|---|---|---|
| 1 | Kasir (POS) | Free | `pos` | Kasir, keranjang, bayar, riwayat. Printer belum teruji. |
| 2 | Scan barcode produk | Starter | `scan_barcode` | Scan kamera (mobile_scanner). |
| 5 | Tipe pesanan (dine-in/takeaway/delivery) | Starter | `tipe_order` | Tipe pesanan dan meja (pengaturan) ada. |
| 7 | Simpan pesanan (hold / open bill) | Free | `hold` | Simpan pesanan (open bill) ada. Belum terhubung ke meja. |
| 17 | DP untuk hutang | Enterprise | `dp_kasbon` | DP untuk kasbon ada (DP minimal persen belum diperiksa). |
| 22 | Cetak struk | Free | `cetak_struk` | Cetak ESC/POS Bluetooth. Belum teruji (tidak ada printer). Pengaturan cetak otomatis setelah bayar belum ditemukan. |
| 23 | Struk ringkas | Enterprise | `struk_ringkas` | Struk ringkas ada. |
| 40 | Kelola paket (bundle) | Enterprise | `bundling` | Bundling produk ada. |
| 41 | Kelola harga grosir | Enterprise | `harga_grosir` | Harga grosir ada. |
| 51 | Bahan baku & resep produk | Professional | `resep` | Resep per produk; stok bahan terpotong saat jual. Perilaku offline belum diverifikasi. |
| 52 | Kelola pelanggan | Starter | `kelola_pelanggan` | CRUD pelanggan dan piutang. |
| 54 | Poin loyalti pelanggan | Professional | `poin_loyalitas` | Poin dan aturan poin ada. Poin hangus per bulan belum diperiksa. |
| 55 | Diskon member | Professional | `diskon_member` | Level member dan diskon member ada. |
| 64 | Laporan Penjualan (sesuai periode langganan) | Free | `laporan_dasar` | Laporan penjualan dengan batas hari per paket. |
| 68 | Buka/tutup shift & rekonsiliasi kas | Starter | `cash_shift` | Buka/tutup shift dan kas ada. Modal awal disarankan (Rp 300.000 untuk F&B) belum diperiksa. |

---

## 6. Gap menu Pengaturan (dari panduan PDF)

Panduan menggambarkan menu Pengaturan dengan 11 tab. Yang belum ada di aplikasi:

| Aspek | Menurut panduan IMOGI | Di aplikasi sekarang |
|---|---|---|
| Struktur | Tab: Kasir, Pembayaran, Struk, Pesanan, Katalog, Stok, Pelanggan, Karyawan, Keuangan, Pribadi, Paket langganan | Pengaturan tersebar di beberapa halaman (menu Lainnya) |
| Simpan | Tersimpan otomatis, tanpa tombol Simpan | Ada tombol Simpan |
| Cakupan | Per cabang (outlet) | Sebagian per outlet |
| Bawaan | Nilai awal otomatis menurut jenis usaha | Tidak ada |
| Reset | Tautan "Kembalikan ke rekomendasi" di tiap tab | Tidak ada |
| Visibilitas | Bagian utama terkunci dengan tombol Upgrade; opsional disembunyikan; tidak relevan tidak tampil | Ada lembar "fitur terkunci"; belum ada aturan inti/opsional per jenis usaha |
| Nama tab | Mengikuti jenis usaha (mis. "Stok & Resep") | Tetap |
| Hak akses | 18 hak akses per peran; peran bawaan Manajer, Kasir, kru (mis. Barista & Dapur), Gudang | Peran dan izin ada; daftar hak belum dicocokkan |
| PIN | PIN owner untuk persetujuan; batas PIN salah 3/5/10x lalu dikunci bertahap | Hitung percobaan gagal dan kunci sementara ada; kunci layar otomatis belum ada |
| Bahasa | Indonesia atau English, struk mengikuti | Belum ada pilihan bahasa |
| Upgrade paket | "Ajukan upgrade", tim IMOGI menghubungi, bayar manual | Ada permintaan upgrade dan checkout Xendit di aplikasi |

**Bawaan untuk jenis usaha F&B menurut panduan** (bahan untuk fitur bawaan nanti):
- Pajak: ditambahkan di atas harga untuk kafe, restoran, katering, roti, minuman, food court; nama pajak PB1.
- Biaya layanan: 5% untuk makan di tempat (kafe dan restoran).
- Struk: format Ringkas untuk kafe, roti, minuman, food court; pesan penutup "Terima kasih, selamat menikmati!".
- Nomor antrian: menyala untuk kafe, minuman, food court, roti; tampilan layar "Siap & disiapkan" untuk kafe dan food court.
- Tiket dapur: cetak otomatis setelah pembayaran, semua kategori kecuali kategori jasa (ongkos kirim, kemasan).
- Alur status pesanan: Baru, Diproses, Siap, (Diantar), Selesai (katering: Dipesan, Dimasak, Siap kirim, Dikirim, Selesai).
- Stok: kafe dan restoran memilih sendiri; saat stok habis "tetap bisa dijual" untuk jenis yang stoknya bukan fitur utama; batas margin 50%.
- Kategori pengeluaran tambahan: Belanja bahan (tanpa stok) [HPP], Gas LPG, Kemasan & plastik.
- Shift: modal awal disarankan Rp 300.000.

---

## 7. Fitur tidak relevan untuk Makanan & Minuman (23)

Fitur ini disembunyikan di aplikasi F&B: 8. Data pembeli & nama STNK/BPKB; 9. Tukar tambah (trade-in) kendaraan; 11. Pembayaran via leasing (DP + pencairan leasing); 12. Invoice tagihan pelanggan (A4, jatuh tempo); 19. Iuran rutin & status bayar anggota; 20. Pengingat iuran via WhatsApp; 21. Kelompok arisan & kocokan oleh admin; 28. Order towing (multi rute & kendaraan, dokumen per kendaraan); 29. Subkon towing ke vendor (1 dokumen per order); 30. Proses dokumen STNK/BPKB & balik nama; 31. Antrian multi loket / ruang; 32. Pilih petugas saat ambil antrian; 33. Cek kendaraan masuk & riwayat servis per plat; 44. Golongan obat & peringatan resep; 45. Durasi layanan; 46. Estimasi selesai per layanan; 47. Data unit kendaraan (no. rangka, no. mesin, spesifikasi); 48. Inspeksi & kondisi unit bekas; 58. Pengingat servis / kontrol berkala; 60. Data anggota (kelas / kelompok); 66. Uang jalan driver otomatis per rute; 75. Komisi & bagi hasil karyawan; 86. Kegiatan, kas & LPJ.

---

## 8. Urutan pembangunan yang diusulkan

Usulan saya berdasarkan jumlah jenis usaha F&B yang menganggapnya inti dan ketergantungan antar fitur. Perlu persetujuan lead.

1. **Fondasi (SELESAI di kode, belum diuji di HP):** katalog 4 paket + 87 fitur dan mode bisnis 7 jenis usaha F&B (migrasi 0009 dan 0010).
2. **Alur pesanan kafe:** varian dan tambahan produk (no. 42), tiket dapur (35), status pesanan (26), nomor antrian beserta layar (34).
3. **Pengaturan terpadu dengan bawaan per jenis usaha:** pajak (4), biaya layanan (6), diskon (3), struk (22 sampai 25), pembayaran (13, 14, 18), stok.
4. **Katalog dan stok:** kategori di kasir (36), margin (37), riwayat mutasi (49), unggah dan ekspor template (38, 39), pengingat kedaluwarsa (50).
5. **Pelanggan dan karyawan:** promo ulang tahun (56), kirim WA (57), survei (59), absensi (62), jadwal dan cuti (63), hak akses (61).
6. **Keuangan:** pengeluaran (67), laba rugi (69), HPP dan margin (72), PPN/PB1 (73), PPh Final (70), settlement QRIS (74).
7. **Akuntansi lanjutan (Enterprise):** jurnal, buku besar, payroll, aset tetap, ekspor akuntansi (76 sampai 85). Pekerjaan besar; sebaiknya pasca Release 1.

---

## 9. Yang perlu dikonfirmasi ke lead

1. Pilih meja, catatan per item, pisah bill, layar dapur, menu habis, dan tip tidak ada di daftar IMOGI. Tetap dikerjakan atau dibuang?
2. Apakah modul Akuntansi (laba rugi sampai ekspor software akuntansi) masuk Release 1 atau sesudahnya?
3. Alur upgrade: manual lewat tim IMOGI (menurut panduan) atau pembayaran Xendit di aplikasi (yang sudah dibangun)?
4. Cetak struk dan tiket dapur: perangkat printer apa yang dijadikan acuan uji?


**KEMAJUAN 2026-11-12 (no. 26 Status pesanan):** estimasi selesai pesanan. Lama pengerjaan bawaan per outlet (menit, 0 = mati) diatur di Pengaturan struk (migrasi 0014, kolom `pengaturan_outlet.estimasi_menit`, ikut sync pull). Halaman Status Pesanan menampilkan "Estimasi selesai HH:mm" (waktu dibuat + menit) selama pesanan Baru/Diproses, dan "Terlambat N mnt" bila lewat. Pengisian > 0 digerbang fitur `status_pesanan`. Belum ada: estimasi per produk (hanya satu angka per outlet), pesan WhatsApp saat siap, dan uji di HP.
