# Pemetaan 64 fitur F&B terhadap bukti uji di HP (per 2026-11-23)

Sumber: tabel `fitur` server (status_dev, 64 fitur relevan F&B dari 87) dan hasil uji langsung di HP pada SIT 22-23 Nov 2026
(dicatat di `docs/perlu_konfirmasi.md`, AT1-AT13). Ini BUKAN QA Passed: status "sudah/sedang" di dashboard adalah laporan
pengembangan; kolom di bawah hanya mencatat apa yang sudah terlihat berjalan di HP. Fitur yang tidak tercantum sebagai
"terbukti" belum tentu rusak; artinya belum saya uji fungsional di HP pada periode ini.

Ringkasan: dari 64 fitur, alur utama terbukti di HP = 11 (17%); terbukti sebagian = 7 (11%); belum diuji = 46 (72%).
Status dashboard: sudah 15, sedang (sebagian) 45, belum 4. Dari 15 yang berstatus "sudah", hanya 4 yang ikut teruji di HP.

## A. Alur utama terbukti di HP (11)
| No | Fitur | Bukti |
|---|---|---|
| 1 | Kasir (POS) | jual tunai, QRIS manual, kartu debit; struk |
| 3 | Kelola diskon | diskon item 10% (struk, laporan, server) dan promo "Uji Hemat 10%" (server mencatat promo) |
| 7 | Simpan pesanan (hold) | simpan lalu buka kembali |
| 15 | Split payment | tunai + kartu; 2 baris pembayaran; indikator Selisih diperbaiki |
| 27 | Terima order, bayar belakangan | order diterima, pelunasan belakangan |
| 38 | Upload produk via template | impor CSV sungguhan |
| 49 | Kelola stok | stok masuk dan opname (mutasi kini tersinkron ke server; opname sungguhan belum ada) |
| 64 | Laporan penjualan | penjualan bersih setelah diskon dan refund |
| 67 | Catat pengeluaran | belanja bahan dan listrik; masuk Laba rugi |
| 68 | Buka/tutup shift | buka, kas masuk/keluar, tutup, kas seharusnya terverifikasi di server |
| 69 | Laporan laba rugi | termasuk refund, diskon, biaya operasional |

## B. Terbukti sebagian (7)
| No | Fitur | Yang terbukti | Belum |
|---|---|---|---|
| 4 | Pajak per produk | service 5% dan PB1 10% terhitung benar | pengaturan per produk |
| 6 | Biaya layanan per tipe pesanan | service dihitung di struk | pemilihan tipe pesanan |
| 10 | Pembayaran QRIS | QRIS manual | QRIS statis bergambar, settlement |
| 13 | Kartu debit/kredit | debit | kredit, no. referensi wajib, refund kartu |
| 22 | Cetak struk | struk di layar, diskon, footer | cetak ke printer |
| 36 | Kelola produk, kategori, harga | produk hasil impor tampil di Kasir | form tambah/ubah produk |
| 61 | Kelola karyawan | peran dan hak akses dibuat | karyawan ber-PIN, peran selain Owner |

## C. Belum diuji di HP (46)
2, 5, 14, 16, 17, 18, 23, 24, 25, 26, 34, 35, 37, 39, 40, 41, 42, 43, 50, 51, 52, 53, 54, 55, 56, 57, 59, 62, 63, 65, 70, 71,
72, 73, 74, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 87.
Catatan: 76, 77, 80, 81 berstatus "belum" (belum dibangun). Banyak layar lain (mis. Tutup buku, Aset tetap, Settlement)
sempat dibuka saat "cek semua layar" tetapi belum diuji fungsionalnya.

## Keterbatasan
- Hanya mencatat yang saya amati sendiri di sesi ini. Uji HP pada sesi sebelumnya yang tidak tercatat di sini tidak dihitung.
- Tidak ada fitur yang ditandai Done/QA Passed oleh dokumen ini.
- Printer, mode offline, kasbon, lintas-HP, dan peran selain Owner belum pernah diuji.

## Pembaruan 2026-11-24 (dashboard admin)
Sejak laporan di atas, uji HP menambah bukti untuk kasbon+cicilan+pelunasan (16), poin dan tukar poin (54), level dan diskon
member (55), karyawan ber-PIN dengan peran Kasir/Barista & Dapur/Gudang (61), selain mutasi stok yang kini tersinkron (49).
Dashboard admin (`backend/app/data/status_fitur.json`, bendera `uji_hp`) kini menandai 16 dari 64 fitur sebagai teruji di HP
(1, 3, 7, 15, 16, 27, 38, 49, 54, 55, 61, 64, 67, 68, 69), masing-masing dengan catatan "UJI HP" yang menyebut buktinya.
Ini bukan QA Passed. Cetak struk ke printer dilaporkan berhasil oleh pengguna sendiri tetapi belum saya amati, jadi fitur 22
tidak ditandai. Tes `test_admin_dashboard.py` kini mewajibkan catatan bukti pada setiap fitur bertanda `uji_hp`.
Tambahan (2026-11-24): atas laporan penguji yang melihat sendiri hasil cetak struk ke printer, fitur 22 (Cetak struk) kini juga
ditandai teruji (total 16). Dasarnya laporan penguji, bukan pengamatan saya; tetap bukan QA Passed formal.
