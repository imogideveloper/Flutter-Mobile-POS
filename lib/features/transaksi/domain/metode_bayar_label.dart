/// Label tampilan utk metodeBayarId - lihat catatan di session_provider.dart:
/// belum ada modul CRUD/seed metode_bayar sungguhan, baru 2 placeholder
/// (tunai & QRIS). TODO: ganti jadi lookup tabel metode_bayar begitu modul
/// itu ada.
///
/// [jumlahPembayaran] > 1 = transaksi split payment (lihat
/// TransaksiDao.pembayaranUtamaTransaksi) - label metode SATU baris saja
/// menyesatkan di kasus itu, tampilkan "Campuran" sebagai gantinya.
String labelMetodeBayar(String? metodeBayarId, {int jumlahPembayaran = 1}) {
  if (jumlahPembayaran > 1) return 'Campuran';
  switch (metodeBayarId) {
    case 'metode-tunai-default':
      return 'Tunai';
    case 'metode-qris-default':
      return 'QRIS';
    default:
      return '-';
  }
}
