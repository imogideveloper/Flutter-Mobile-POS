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
