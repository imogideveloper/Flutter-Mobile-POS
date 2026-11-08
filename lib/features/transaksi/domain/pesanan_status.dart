import '../data/local/tables/transaksi_table.dart' show StatusPesanan;

/// Satu pesanan di halaman Status Pesanan.
class PesananStatus {
  const PesananStatus({
    required this.id,
    required this.nomorStruk,
    required this.tanggal,
    required this.status,
    required this.ringkasanItem,
    this.nomorAntrean,
    this.pelangganId,
  });

  final String id;
  final String nomorStruk;
  final String? nomorAntrean;
  final int tanggal;
  final StatusPesanan status;

  /// Mis. "2x Kopi Susu, 1x Roti Bakar".
  final String ringkasanItem;
  final String? pelangganId;

  /// Judul yang dilihat pelayan: nomor antrian bila ada, kalau tidak nomor struk.
  String get judul => nomorAntrean ?? nomorStruk;
}
