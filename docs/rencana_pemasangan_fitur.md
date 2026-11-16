# Rencana Memasang Seluruh Fitur Dashboard IMOGI ke Aplikasi

Disusun 2026-11-14. Acuan: dashboard `IMOGI POS Menu & Fitur.html` (87 fitur, 13 modul, 4 paket, matriks inti/opsional per jenis usaha). Status per fitur: `docs/gap_imogi.md`.

## 1. Arti "terpasang"

Sebuah fitur dihitung **terpasang** bila: (a) bisa dibuka dan dipakai di aplikasi, (b) lulus tes otomatis, dan (c) sudah lulus uji di HP. Saat ini baru (a) dan (b) yang bisa dibuktikan, jadi tidak ada fitur yang resmi "Lengkap" sampai ada uji HP. Fitur yang butuh sesuatu dari luar (kunci Xendit, printer Bluetooth) ditandai **Terblokir**.

## 2. Cakupan

| | Jumlah |
|---|---|
| Fitur di dashboard | 87 |
| Relevan untuk Makanan & Minuman (7 jenis usaha) | 64 |
| Tidak relevan untuk semua jenis usaha F&B (alat bantu retail, jasa, dst.) | 23 |
| Dari 64 itu: lengkap (belum uji HP) | 15 |
| Dari 64 itu: sebagian | 35 |
| Dari 64 itu: belum ada | 14 |

**Asumsi yang perlu dikonfirmasi:** 23 fitur non-F&B tidak dibangun, sesuai arahan lead 2026-11-08 ("aplikasi hanya modul Makanan & Minuman"). Bila seluruh 87 harus terpasang, tambahan 23 fitur itu masuk rencana tersendiri (lihat bagian 6).

## 3. Urutan pengerjaan yang diusulkan

Ukuran: S = kecil (satu layar atau satu aturan), M = sedang (layar baru dan server), L = besar (beberapa layar dan model data saling bergantung).

### Batch A, menyempurnakan pembayaran, struk, dan kasir (15 fitur sebagian, ukuran S sampai M)
| No | Fitur | Yang masih kurang | Ukuran |
|---|---|---|---|
| 3 | Kelola diskon | Tombol cepat diskon manual, izin diskon per item, batas diskon dengan PIN owner | M |
| 4 | Pajak per produk | Status pajak usaha, nama pajak (PB1/PPN), cara hitung termasuk/ditambahkan | M |
| 6 | Biaya layanan per tipe pesanan | Bawaan 5% makan di tempat | S (bergantung Batch B) |
| 13 | Kartu debit/kredit (EDC) | Jenis kartu, daftar mesin EDC, kewajiban no. referensi/4 digit | M |
| 14 | Transfer bank | Daftar rekening (bank, nomor, atas nama) | S |
| 15 | Split payment | Penggerbangan paket; QRIS dikecualikan | S |
| 16 | Hutang (bon) | Limit bon per pelanggan dan penahanan bon baru | S |
| 18 | Label jenis pembayaran | Label tujuan (GoPay, OVO, bank) untuk rekonsiliasi | M |
| 24 | Logo di struk | Gaya logo siap pakai; BUG-012 | S |
| 25 | Catatan tambahan di struk | Teks maks 300 karakter di bawah struk | S |
| 27 | Terima order, bayar belakangan | Tombol Terima Order dan pilihan kapan membayar | M |
| 10 | QRIS | QRIS statis dari gambar yang diunggah usaha; QRIS dinamis **terblokir** kunci Xendit | M |
| 35 | Tiket dapur | Per stasiun, auto-print terpisah; uji printer **terblokir** perangkat | M |
| 26, 34 | Status pesanan, nomor antrian | Layar antrian, panggilan suara, nama di layar antrian | M |
| 36 | Kelola produk | Urutan tab kasir terpisah | S |

### Batch B, mekanisme pemisahan per jenis usaha (ukuran L, mengerjakan "persempit ke jenis usaha")
Data klasifikasi inti/opsional/tidak relevan untuk tujuh jenis usaha sudah ada di database (`fitur_kebutuhan`) tetapi belum dipakai kode (lihat `docs/perlu_konfirmasi.md` M1 sampai M3). Isinya:
1. Server mengirim klasifikasi fitur untuk jenis usaha toko, lewat sync.
2. Aplikasi menyembunyikan atau menandai menu sesuai klasifikasi (keputusan lead: disembunyikan atau diberi tanda).
3. Nilai bawaan pengaturan per jenis usaha (pajak, service, struk ringkas, nomor antrian, tiket dapur, modal awal shift).
4. Menu Pengaturan versi IMOGI (11 tab, simpan otomatis, "Kembalikan ke rekomendasi").
5. Peran bawaan dan 18 hak akses IMOGI, termasuk Barista & Dapur.

### Batch C, katalog, stok, multi-outlet
| No | Fitur | Ukuran |
|---|---|---|
| 43 | Jual per kemasan (pcs, dus, pak) | M |
| 50 | Pengingat kedaluwarsa produk | M |
| 49, 36 | Sisa riwayat stok (filter tanggal), tab kasir | S |
| 87 | Multi-outlet: tampilan ganti outlet | M |
| 38, 39, 53 | Impor/ekspor lanjutan (.xlsx, perbarui data lama) | S |

### Batch D, pelanggan dan karyawan
| No | Fitur | Ukuran |
|---|---|---|
| 57 | Kirim WhatsApp massal | M (butuh keputusan API WhatsApp) |
| 59 | Survei pelanggan | L (halaman/layar pelanggan) |
| 56 | Promo ulang tahun: penerapan otomatis, pemberitahuan | S |
| 62, 63 | Absensi (foto, lokasi), tukar jadwal, jam shift kustom | M |
| 61 | Hak akses lengkap | termasuk Batch B |

### Batch E, laporan
| No | Fitur | Ukuran |
|---|---|---|
| 65 | Grafik tren penjualan | S |
| 71 | Piutang dan hutang usaha (AR/AP) | M |
| 74 | Settlement dan rekonsiliasi QRIS/e-wallet | M (bergantung data gateway) |
| 67, 69, 70, 72, 73 | Penyempurnaan: offline, ekspor, edit | M |

### Batch F, akuntansi Enterprise (rangkaian saling bergantung, ukuran L)
Urutan wajib: 80 (akun dan jurnal umum) → 81 (buku besar, neraca, arus kas) → 82 (anggaran) → 83 (aset tetap) → 84 (konsolidasi) → 85 (ekspor ke software akuntansi). Terpisah: 76 dan 77 (payroll, BPJS, PPh 21), 78 (tutup buku), 79 (pendapatan di muka). Rumus keuangan harus divalidasi akuntan sebelum dipakai.

## 4. Ketergantungan dan penghalang
- **Terblokir:** QRIS dinamis (kunci Xendit), uji printer Bluetooth (perangkat), rilis Play Store (keystore, server produksi).
- **Butuh keputusan lead:** Release Scope (TASK-104), disembunyikan atau ditandai untuk fitur tidak relevan, rumus laba rugi dan pajak, matriks izin, API WhatsApp.
- **Syarat semuanya:** uji di HP. Tanpa itu tidak ada fitur yang naik dari Sebagian.

## 5. Cara mengukur kemajuan
Tiap fitur selesai dicatat di tiga tempat: `docs/gap_imogi.md` (status), Tracker `Feature Inventory` dan `Gap Imogi`, serta test case di workbook QA. Angka ringkasan dihitung ulang tiap batch.

## 6. Bila seluruh 87 fitur harus terpasang
Tambahan 23 fitur non-F&B (mis. fitur khusus retail dan jasa) dikerjakan setelah Batch F dan disembunyikan untuk ketujuh jenis usaha F&B lewat mekanisme Batch B. Daftar rinci 23 fitur itu ada di `docs/gap_imogi.md` bagian 7.
