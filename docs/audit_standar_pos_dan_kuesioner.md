# Audit Standar POS, Jenis Usaha, Paket + Kuesioner Uji HP

Dibuat 2026-11-18. Dasar: pembacaan kode, data database dev (migrasi 0034), `docs/gap_imogi.md`, dan `docs/perlu_konfirmasi.md`. **Ini bukan hasil uji HP.** Tidak ada fitur yang boleh naik ke "Lengkap" sampai kuesioner bagian 5 dijawab dari HP.

---

## 1. Ringkasan temuan

| # | Temuan | Bukti | Tingkat |
|---|---|---|---|
| 1 | Katalog paket konsisten: 4 paket (Free 20 fitur, Starter 44, Professional 64, Enterprise 87) dari 87 fitur | Query database dev | Baik |
| 2 | Semua kode fitur yang dipakai Flutter dan `fitur_map.py` ada di database (tidak ada kode yatim) | Perbandingan daftar kode | Baik |
| 3 | Seluruh 87 fitur punya klasifikasi inti/opsional/tidak relevan untuk 7 jenis usaha F&B | Tabel `fitur_kebutuhan` | Baik |
| 4 | **Selama masa trial semua toko mendapat paket tertinggi**, jadi pembatasan paket tidak akan terlihat saat uji di akun baru | `paket_efektif` di `fitur_service.py` | Perlu dipahami saat uji |
| 5 | 5 fitur berbayar belum ditemukan penjaga paketnya: `cash_shift` (Starter), `product_options` (Starter, varian/tambahan), `payables` (Professional), `scan_barcode`, `kelola_pelanggan`. **Diperbarui 2026-11-18:** `product_options` sudah dikunci di server dan aplikasi (604 tes backend dan 539 tes Flutter lulus). Empat lainnya menunggu lead (AO2, AO3 di `perlu_konfirmasi.md`) karena menyentuh alur inti | Pencarian kode: tidak ada `require_fitur` atau `FiturTerkunci` untuk kode ini | Sebagian selesai |
| 6 | Penyembunyian per jenis usaha hanya bekerja untuk kontrol yang dibungkus `FiturTerkunci`. Klasifikasi "inti" vs "opsional" belum dipakai untuk apa pun di tampilan, hanya "tidak relevan" | `feature_gate_provider.dart`, `fitur_terkunci.dart` | Sebagian |
| 7 | Bawaan per jenis usaha di server baru mencakup: pajak PB1 10% (6 dari 7 jenis), biaya layanan 5% hanya Kafe dan Restoran, tiga tipe pesanan, pesan penutup struk | `bawaan_usaha.py` | Sebagian |
| 8 | Fitur akuntansi baru (settlement, aset tetap, anggaran, ekspor, tutup buku, deposit) online-only, berbeda dari kasir yang offline-first | Keputusan D1 di `perlu_konfirmasi.md` | Catatan |
| 9 | Fitur kasir standar yang belum ada (menurut `gap_imogi.md`): pisah/gabung bill, layar dapur (KDS), menu habis (sold out), tip. Perlu konfirmasi lead apakah dikerjakan | `gap_imogi.md` temuan 5 | Belum ada |
| 10 | Printer Bluetooth belum teruji (tidak ada printer), QRIS dinamis terblokir (kunci Xendit kosong) | F2 | Belum bisa diuji |
| 11 | Dokumentasi tertinggal: `fitur_map.py` menulis "1 Pro, 2 Bisnis" padahal ada tingkat 3, dan seed tes memakai 3 paket lama | Komentar kode, A8 | Rapikan nanti |

Catatan metode untuk temuan 5: saya mencari kode fitur di `lib/` dan `backend/app/`. Bisa saja penjaga ada dengan bentuk lain, jadi ini perlu dikonfirmasi lewat uji akun Free di HP (pertanyaan G1 sampai G4).

## 2. Standar aplikasi POS: yang ada dan yang belum

| Kemampuan kasir standar | Status menurut kode | Bukti uji HP |
|---|---|---|
| Login PIN per kasir, peran dan izin | Ada | Belum |
| Buka/tutup shift, kas masuk/keluar | Ada | Belum |
| Keranjang, varian dan tambahan, catatan, diskon manual per item | Ada | Belum |
| Pajak, biaya layanan per tipe pesanan | Ada | Belum |
| Tipe pesanan dan meja | Ada | Belum |
| Simpan/tahan pesanan, terima order bayar belakangan | Ada | Belum |
| Bayar tunai, QRIS statis, kartu, split pembayaran | Ada | Belum |
| Kasbon dan DP | Ada | Belum |
| Struk: cetak, bagikan, logo, ringkas, nomor antrean | Ada, printer belum teruji | Belum |
| Tiket dapur dan status pesanan | Ada | Belum |
| Refund dan void | Ada | Belum |
| Stok: masuk, opname, transfer, kedaluwarsa, resep, bundling | Ada | Belum |
| Pelanggan: member, poin, diskon, impor, WA massal, survei, deposit | Ada | Belum |
| Laporan harian, laba rugi, pajak, margin, pengeluaran | Ada | Belum |
| Offline-first dan sync | Ada | Belum |
| Pisah/gabung bill, KDS, sold out, tip | Belum ada | Tidak berlaku |
| Payroll, jurnal, buku besar | Belum ada (butuh keputusan akuntan) | Tidak berlaku |

## 3. Pembatasan paket: titik yang perlu diuji

- Server menolak dengan 403 `fitur_terkunci` untuk 34 fitur berbayar yang terdaftar di `fitur_map.py`. Backend ini sudah dites otomatis.
- Aplikasi menampilkan gembok lewat `FiturTerkunci`. Tampilan itu hanya bergantung pada cache paket di HP. Saat saya mengecek, lencana di Lainnya masih bertuliskan "Gratis" padahal toko sedang trial. Jadi ada selisih antara paket yang tampil dan paket yang berlaku. Ini harus dicek di HP (G1).

## 4. Jenis usaha: titik yang perlu diuji

Daftar toko baru untuk beberapa jenis usaha dan bandingkan bawaannya: pajak PB1, biaya layanan, tipe pesanan, dan menu yang tersembunyi. Jenis yang paling berbeda dari Kafe: Bahan Segar & Makanan Beku (FRZ, tanpa PB1 bawaan) dan Kios & Food Court (STL).

---

## 5. Kuesioner uji HP

Cara mengisi: untuk tiap baris tulis **OK** (berjalan), **GAGAL** (sebutkan apa yang terjadi), **TIDAK ADA** (menu/fitur tidak ketemu), atau **SKIP** (tidak bisa diuji, mis. tanpa printer). Kolom "Catatan" untuk layar yang aneh, teks terpotong, atau salah ketik. Jangan menandai OK bila tidak dicoba.

Penting sebelum mulai: untuk bagian G (paket), pakai toko yang **masa trialnya sudah habis** atau minta lead menonaktifkan trial di pengaturan platform. Kalau tidak, semua fitur akan terbuka dan pembatasan tidak terlihat.

### A. Masuk dan perangkat
| Kode | Uji | Hasil | Catatan |
|---|---|---|---|
| A1 | Pilih akun lalu masuk dengan PIN | | |
| A2 | Salah PIN: pesan kesalahan jelas, tidak terkunci selamanya | | |
| A3 | Tutup aplikasi sepenuhnya lalu buka lagi: diminta pilih akun lagi | | |
| A4 | "Lupa PIN kasir?" dan alur OTP | | |
| A5 | Login Administrator (email atau nama pengguna), buka dashboard | | |
| A6 | Matikan data/wifi, buat transaksi, nyalakan lagi, tekan Sync: transaksi terkirim | | |

### B. Alur kasir
| Kode | Uji | Hasil | Catatan |
|---|---|---|---|
| B1 | Buka shift dengan kas awal | | |
| B2 | Tambah produk ke keranjang, ubah jumlah, hapus | | |
| B3 | Produk dengan varian dan tambahan (ukuran, gula, topping) | | |
| B4 | Catatan pada item dan catatan struk | | |
| B5 | Diskon manual per item dan promo | | |
| B6 | Pajak PB1 dan biaya layanan muncul benar di total | | |
| B7 | Pilih tipe pesanan dan meja | | |
| B8 | Simpan/tahan pesanan lalu lanjutkan | | |
| B9 | Terima order, bayar belakangan | | |
| B10 | Bayar tunai: kembalian benar | | |
| B11 | Bayar QRIS statis | | |
| B12 | Bayar kartu dengan nomor referensi | | |
| B13 | Split pembayaran (dua metode) | | |
| B14 | Kasbon dan DP | | |
| B15 | Struk: tampilan, bagikan, WhatsApp | | |
| B16 | Cetak struk ke printer Bluetooth (SKIP bila tanpa printer) | | |
| B17 | Nomor antrean dan tiket dapur | | |
| B18 | Status pesanan (diproses, siap, diantar) | | |
| B19 | Refund sebagian dan penuh | | |
| B20 | Tutup shift: selisih kas dihitung benar | | |

### C. Produk dan stok
| Kode | Uji | Hasil | Catatan |
|---|---|---|---|
| C1 | Tambah, ubah, nonaktifkan produk dan kategori | | |
| C2 | Daftar Produk: apakah semua produk benar-benar "Habis" atau hanya data uji | | |
| C3 | Resep, bundling, harga grosir, kemasan | | |
| C4 | Barcode: pindai dan cari | | |
| C5 | Impor dan ekspor produk (CSV) | | |
| C6 | Stok masuk, opname, transfer antar outlet | | |
| C7 | Kedaluwarsa: tambah batch, lihat pengingat | | |
| C8 | Harga beli dan margin, laporan margin | | |

### D. Pelanggan
| Kode | Uji | Hasil | Catatan |
|---|---|---|---|
| D1 | Tambah pelanggan, impor CSV | | |
| D2 | Level member, aturan poin, poin bertambah setelah transaksi | | |
| D3 | Diskon member dan promo ulang tahun | | |
| D4 | Kirim WA massal | | |
| D5 | Survei: buat, isi, lihat hasil | | |
| D6 | Deposit: top-up, pakai, koreksi, riwayat | | |

### E. Laporan dan keuangan
| Kode | Uji | Hasil | Catatan |
|---|---|---|---|
| E1 | Laporan harian: tab Hari ini, 7 hari, 30 hari, Atur | | |
| E2 | Angka laporan sama dengan transaksi yang dibuat | | |
| E3 | Riwayat: ringkasan Penjualan dan Transaksi, cari struk | | |
| E4 | Laba rugi, rekap pajak, PPh final | | |
| E5 | Pengeluaran: catat dan lihat | | |
| E6 | Settlement: catat dan rekonsiliasi | | |
| E7 | Aset tetap: tambah, ubah angka, lihat penyusutan | | |
| E8 | Anggaran: tetapkan, salin dari bulan lalu | | |
| E9 | Ekspor CSV akuntansi lalu bagikan | | |
| E10 | Tutup buku: kunci periode, coba catat pengeluaran di periode terkunci (harus ditolak), lalu buka kembali | | |

### F. Tim dan hak akses
| Kode | Uji | Hasil | Catatan |
|---|---|---|---|
| F1 | Tambah karyawan dan atur peran | | |
| F2 | Masuk sebagai Kasir: tab Produk dan Laporan tidak tampil | | |
| F3 | Kasir tidak bisa membuka menu yang bukan haknya lewat jalur lain | | |
| F4 | Absensi dan jadwal shift | | |

### G. Pembatasan paket (pakai toko tanpa trial)
| Kode | Uji | Hasil | Catatan |
|---|---|---|---|
| G1 | Lencana paket di Lainnya sesuai paket sebenarnya setelah Sync | | |
| G2 | Paket Free: menu berbayar tampil redup dengan gembok dan menyebut paket minimal | | |
| G3 | Paket Free: coba buka fitur berbayar, muncul pesan terkunci, bukan error mentah | | |
| G4 | Paket Free: shift, varian/tambahan, hutang-piutang, barcode, kelola pelanggan. Apakah boleh dipakai? (Lihat temuan 5; catat hasilnya apa adanya) | | |
| G5 | Paket Free: laporan hanya mencakup batas hari yang ditetapkan | | |
| G6 | Naikkan paket lalu Sync: gembok hilang | | |
| G7 | Turunkan paket: data tidak hilang, hanya fitur terkunci lagi | | |

### H. Per jenis usaha (daftar toko baru untuk tiap jenis)
| Kode | Uji | Hasil | Catatan |
|---|---|---|---|
| H1 | Kafe: PB1 10%, Service Charge 5% hanya di "Makan di tempat" | | |
| H2 | Restoran: sama seperti Kafe | | |
| H3 | Roti/Kue, Katering, Minuman, Kios: PB1 ada, biaya layanan tidak ada | | |
| H4 | Bahan Segar & Beku: tanpa PB1 bawaan | | |
| H5 | Menu "tidak relevan" tersembunyi untuk jenis usaha itu (mis. tiket dapur untuk Bahan Segar) | | |
| H6 | Peran bawaan dan nama tab (mis. "Stok & Resep") sesuai jenis usaha | | |

### I. Tampilan
| Kode | Uji | Hasil | Catatan |
|---|---|---|---|
| I1 | Lainnya: grup, ikon, dan keterangan tidak terpotong | | |
| I2 | Produk: chip, lencana Habis, tombol "+ Produk" | | |
| I3 | Riwayat dan Laporan dengan data: kartu angka mudah dibaca | | |
| I4 | Layar kosong dan layar error tampil rapi | | |
| I5 | Teks terpotong atau tumpang tindih di layar mana pun (sebutkan layarnya) | | |

---

## 6. Pertanyaan untuk Anda (tentukan prioritas uji)

1. Dari bagian A sampai I, bagian mana yang ingin Anda uji lebih dulu? Saran saya: A, B, G.
2. Apakah ada printer Bluetooth yang bisa dipakai untuk B16?
3. Bisakah Anda membuat toko uji dengan trial nonaktif untuk bagian G?
4. Jenis usaha mana yang paling dipakai target pelanggan, supaya bagian H difokuskan ke sana?
5. Fitur mana di bagian 2 yang menurut Anda wajib ada sebelum rilis (pisah bill, sold out, tip, KDS)? Jawaban Anda saya bawa ke lead.
