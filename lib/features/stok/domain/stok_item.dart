/// Model domain saldo stok, sudah membawa nama produk hasil join supaya
/// UI tidak perlu query terpisah per baris.
class StokItem {
  const StokItem({
    required this.id,
    required this.outletId,
    required this.produkId,
    this.varianId,
    required this.produkNama,
    required this.jumlah,
    required this.batasMinimum,
    required this.hppRataRata,
  });

  final String id;
  final String outletId;
  final String produkId;
  final String? varianId;
  final String produkNama;
  final double jumlah;
  final double batasMinimum;
  final int hppRataRata;

  bool get stokMenipis => jumlah <= batasMinimum;
}
