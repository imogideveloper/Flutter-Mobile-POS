/// Label tampilan untuk metodeBayarId.
///
/// [nama] = peta id metode bayar -> nama dari tabel `metode_bayar` lokal (hasil pull-sync).
/// Id metode bayar asli dari server berbentuk UUID, jadi namanya HARUS dicari di peta itu
/// (BUG-015: dulu hanya dua id placeholder yang dikenali, sehingga semua transaksi asli tampil '-').
///
/// [jumlahPembayaran] > 1 = transaksi split payment (lihat
/// TransaksiDao.pembayaranUtamaTransaksi) - label metode SATU baris saja
/// menyesatkan di kasus itu, tampilkan "Campuran" sebagai gantinya.
String labelMetodeBayar(
  String? metodeBayarId, {
  int jumlahPembayaran = 1,
  Map<String, String>? nama,
}) {
  if (jumlahPembayaran > 1) return 'Campuran';
  final dariTabel = metodeBayarId == null ? null : nama?[metodeBayarId];
  if (dariTabel != null && dariTabel.trim().isNotEmpty) return dariTabel;
  // Id placeholder lama (data dari era sebelum ada tabel metode bayar).
  switch (metodeBayarId) {
    case 'metode-tunai-default':
      return 'Tunai';
    case 'metode-qris-default':
      return 'QRIS';
    default:
      return '-';
  }
}
