import '../data/local/tables/mutasi_stok_table.dart' show MutasiJenis;

/// Model domain satu baris mutasi stok, sudah membawa nama produk hasil
/// join - dipakai kartu "Mutasi terakhir" di halaman Stok.
class MutasiItem {
  const MutasiItem({
    required this.id,
    required this.produkNama,
    required this.jenis,
    required this.qty,
    required this.catatan,
    required this.createdAt,
    this.produkId = '',
    this.saldoSetelah,
  });

  final String id;
  final String produkId;

  /// Saldo stok sesudah mutasi ini (null bila tidak tercatat, mis. data lama).
  final double? saldoSetelah;
  final String produkNama;
  final MutasiJenis jenis;
  final double qty;
  final String? catatan;
  final int createdAt;

  bool get masuk => qty > 0;
}
