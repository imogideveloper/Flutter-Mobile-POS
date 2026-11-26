# Backlog Release 2 (penyempurnaan, bukan syarat Release 1)

Disusun 2026-11-26. Kriteria Release 1 dari pengguna: fitur dianggap selesai bila sudah cukup (bukan setengah jadi),
langsung bisa dipakai UMKM lokal dengan standar POS umum, dan lulus uji di HP. Butir di bawah adalah sisa
penyempurnaan dari 17 fitur yang dinaikkan menjadi "sudah" pada tanggal itu. Sumber: catatan pengembangan di
`backend/app/data/status_fitur.json` dan temuan di `docs/perlu_konfirmasi.md`.

| No | Fitur | Penyempurnaan untuk Release 2 |
|---|---|---|
| 3 | Kelola diskon | Batas diskon kasir tanpa PIN; tombol cepat yang bisa diatur; diskon level transaksi (nominal); diskon manual ikut saat pesanan tersimpan dibuka kembali |
| 4 | Pajak per produk | Nilai bawaan per jenis usaha |
| 6 | Biaya layanan per tipe pesanan | Usaha yang sudah terdaftar otomatis dapat bawaan; pengaturan bawaan lain per jenis usaha |
| 15 | Bayar campur | - |
| 16 | Pembayaran hutang (bon) | Kasbon dan pelunasan saat offline; pembayaran susulan langsung tersinkron |
| 18 | Label jenis pembayaran | Label pada QRIS statis dan bayar campur; rekonsiliasi terhadap settlement |
| 27 | Terima order, bayar belakangan | Pilihan jatuh tempo; nota order khusus; tukar poin dan QRIS saat pelunasan |
| 34 | Nomor antrian | Panggilan suara, layar antrian, nama di layar antrian |
| 35 | Cetak tiket dapur | Printer terpisah per stasiun; cetak otomatis terpisah |
| 36 | Kelola produk, kategori & harga | Urutan tab kasir terpisah dari urutan kategori |
| 37 | Harga beli & margin | Izin khusus untuk melihat harga beli |
| 38 | Upload produk via template | - |
| 42 | Varian & tambahan | Urutan opsi bisa digeser; tambahan khusus per produk; izin kelola terpisah |
| 49 | Kelola stok | Ekspor riwayat; riwayat per varian; layar opname bertahap |
| 61 | Kelola karyawan | Uji peran Manajer; penegakan izin bon.jual, bon.lihat, pesanan.status, persetujuan.pin; pembatasan juga di server (AT26d) |
| 67 | Catat pengeluaran | Mode offline; ubah data; foto nota; pengeluaran berulang |
| 69 | Laporan laba rugi | Samakan dengan Laporan keuangan (penyusutan aset tetap) |

## Tambahan 2026-11-26 (25 fitur yang lulus uji cepat di HP)

| No | Fitur | Penyempurnaan untuk Release 2 |
|---|---|---|
| 13 | Kartu debit/kredit | Daftar mesin EDC |
| 50 | Pengingat kedaluwarsa | Pemberitahuan terjadwal; batch berkurang otomatis saat penjualan (FIFO); batch dari pembelian |
| 53 | Impor pelanggan | Memperbarui pelanggan lama; impor poin dan level |
| 56 | Promo ulang tahun | Pemberitahuan ke pelanggan; validasi server saat checkout |
| 59 | Survei pelanggan | Tampil di struk atau WhatsApp; tautan ke transaksi |
| 62 | Absensi | Foto, lokasi, keterlambatan dari jadwal, koreksi, offline |
| 63 | Jadwal & cuti | Tukar jadwal; jam shift kustom; shift lintas tengah malam; pemberitahuan |
| 72 | HPP & margin | Ekspor; laporan per kategori |
| 73 | Rekap PPN/PB1 | Ekspor; PPN masukan/keluaran; pelaporan SPT |
| 74 | Settlement | Impor otomatis dari penyedia pembayaran |
| 78 | Tutup buku | Jurnal penutup dan saldo awal tahun baru |
| 79 | Deposit pelanggan | Deposit sebagai metode bayar di kasir; membership berjangka |
| 80 | Bagan akun | Jurnal umum (akun tetap sesuai keputusan lead) |
| 81 | Laporan keuangan | Saldo awal kas; setoran modal dan prive; utang pajak; ekspor PDF |
| 82 | Anggaran | Proyeksi arus kas dengan piutang/utang; anggaran per outlet |
| 83 | Aset tetap | Metode saldo menurun; pelepasan atau penjualan aset |
| 84 | Konsolidasi | Neraca dan arus kas per outlet |
| 85 | Ekspor akuntansi | Format khusus Jurnal/Accurate/Zahir |
| 69, 65, Laporan | Laporan | Samakan laba kotor di tab Laporan (Rp338.000) dengan Laba rugi dan Laporan keuangan (Rp308.400): tab Laporan belum mengurangkan diskon transaksi |
