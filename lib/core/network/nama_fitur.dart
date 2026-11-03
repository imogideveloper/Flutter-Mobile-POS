/// Nama tampilan per kode fitur - disalin dari `nama` di seed 32 fitur
/// resmi backend (`backend/app/core/seed.py`/migrasi 0001) supaya pesan
/// di bottom sheet "Tersedia di paket X" konsisten dgn istilah yang
/// dipakai server, bukan menampilkan kode mentah ke pengguna.
const Map<String, String> namaFitur = {
  'pos': 'Kasir (POS)',
  'cetak_struk': 'Cetak struk',
  'scan_barcode': 'Scan produk',
  'kelola_stok': 'Kelola stok produk',
  'kelola_pelanggan': 'Kelola pelanggan',
  'laporan_dasar': 'Laporan penjualan',
  'qris': 'Pembayaran QRIS',
  'kasbon': 'Bayar dengan utang (kasbon)',
  'tren_penjualan': 'Tren penjualan',
  'multi_outlet': 'Multi-outlet',
  'resep': 'Bahan baku dan resep',
  'ekspor_impor': 'Ekspor dan unggah template',
  'diskon': 'Kelola diskon',
  'pajak_per_produk': 'Pajak per produk',
  'tipe_order': 'Tipe pesanan',
  'kelola_karyawan': 'Kelola karyawan',
  'poin_loyalitas': 'Poin loyalitas pelanggan',
  'diskon_member': 'Diskon member',
  'survei': 'Survei pelanggan',
  'absensi': 'Absensi karyawan',
  'struk_ringkas': 'Struk ringkas',
  'tiket_dapur': 'Cetak tiket dapur',
  'catatan_struk': 'Catatan tambahan di struk',
  'service_per_tipe_order': 'Service fee per tipe pesanan',
  'status_pesanan': 'Status pesanan',
  'dp_kasbon': 'DP untuk kasbon',
  'nomor_antrean': 'Nomor antrean',
  'label_pembayaran': 'Label metode pembayaran',
  'logo_struk': 'Logo usaha di struk',
  'bundling': 'Kelola bundling produk',
  'pengingat_kedaluwarsa': 'Pengingat kedaluwarsa produk',
  'harga_grosir': 'Harga grosir',
};

String namaTampilanFitur(String kode) => namaFitur[kode] ?? kode;
