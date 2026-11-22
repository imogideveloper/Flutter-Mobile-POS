/// Nama dan keterangan hak akses yang tampil di layar Peran (acuan: panduan IMOGI hlm. 28-29).
/// Kode yang belum ada di sini jatuh ke deskripsi dari server.
class LabelIzin {
  const LabelIzin(this.judul, this.keterangan);

  final String judul;
  final String keterangan;
}

const labelIzin = <String, LabelIzin>{
  'transaksi.buat': LabelIzin('Jualan di Kasir', 'Membuat transaksi penjualan.'),
  'transaksi.diskon': LabelIzin('Diskon manual tanpa persetujuan', 'Memberi diskon sendiri tanpa PIN atasan.'),
  'transaksi.void': LabelIzin('Batalkan transaksi (void)', 'Membatalkan transaksi yang sudah dibayar.'),
  'transaksi.refund': LabelIzin('Refund', 'Mengembalikan uang pelanggan.'),
  'transaksi.batal_pesanan': LabelIzin('Batalkan pesanan tersimpan', 'Menyetujui pembatalan pesanan yang belum dibayar.'),
  'bon.jual': LabelIzin('Jual bon / DP', 'Menjual dengan bon atau uang muka.'),
  'bon.lihat': LabelIzin('Daftar bon', 'Melihat daftar bon pelanggan.'),
  'pesanan.status': LabelIzin('Status pesanan dan antrian', 'Mengubah status pesanan di dapur atau bar.'),
  'persetujuan.pin': LabelIzin('Menyetujui dengan PIN', 'PIN-nya dapat dipakai untuk menyetujui tindakan karyawan lain.'),
  'pelanggan.kelola': LabelIzin('Data pelanggan', 'Menambah dan mengubah pelanggan.'),
  'produk.kelola': LabelIzin('Kelola produk dan harga', 'Menambah, mengubah, dan menghapus produk.'),
  'produk.lihat_margin': LabelIzin('Lihat harga beli dan margin', 'Melihat HPP dan margin produk.'),
  'stok.kelola': LabelIzin('Stok dan barang masuk', 'Mencatat stok masuk, penyesuaian, dan transfer.'),
  'pembelian.kelola': LabelIzin('Pembelian dari supplier', 'Mengelola pesanan pembelian.'),
  'stok.opname_posting': LabelIzin('Posting stok opname', 'Menyelesaikan stok opname sehingga stok berubah.'),
  'promo.kelola': LabelIzin('Promo dan pajak', 'Mengatur promo dan pajak.'),
  'laporan.lihat': LabelIzin('Laporan penjualan', 'Melihat laporan penjualan dan akuntansi dasar.'),
  'laporan.keuangan': LabelIzin('Laba rugi, pajak, dan margin', 'Melihat laba rugi, rekap pajak, dan PPh Final.'),
  'pengeluaran.catat': LabelIzin('Catat pengeluaran', 'Mencatat biaya operasional.'),
  'shift.buka_tutup': LabelIzin('Buka/tutup shift', 'Membuka dan menutup shift kasir.'),
  'kas.keluar_masuk': LabelIzin('Kas masuk dan keluar', 'Mencatat uang masuk dan keluar dari laci kas.'),
  'pengguna.kelola': LabelIzin('Kelola karyawan dan peran', 'Menambah karyawan dan mengatur peran.'),
  'pengaturan.kelola': LabelIzin('Pengaturan', 'Mengubah pengaturan toko dan outlet.'),
};

const judulModulIzin = <String, String>{
  'penjualan': 'Penjualan',
  'produk': 'Produk',
  'stok': 'Stok',
  'laporan': 'Laporan dan keuangan',
  'pengaturan': 'Karyawan dan pengaturan',
};
