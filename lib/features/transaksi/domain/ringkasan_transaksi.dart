import '../data/local/tables/transaksi_table.dart' show TransaksiStatus;

/// Satu baris di layar Riwayat - transaksi + info ringkas yang perlu query
/// tambahan (jumlah item, metode bayar) tanpa harus join berat di DAO.
class RingkasanTransaksi {
  const RingkasanTransaksi({
    required this.id,
    required this.nomorStruk,
    required this.tanggal,
    required this.status,
    required this.total,
    required this.jumlahItem,
    this.pelangganId,
    this.metodeBayarId,
    this.jumlahPembayaran = 1,
  });

  final String id;
  final String nomorStruk;
  final int tanggal;
  final TransaksiStatus status;
  final int total;
  final int jumlahItem;
  final String? pelangganId;
  final String? metodeBayarId;
  final int jumlahPembayaran;
}
