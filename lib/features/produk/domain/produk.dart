import '../data/local/tables/produk_table.dart' show ProdukTipe;

/// Model domain Produk, lepas dari tipe row drift (ProdukRow) supaya layer
/// UI/domain tidak bergantung langsung pada detail generated code database.
class Produk {
  const Produk({
    required this.id,
    required this.tokoId,
    this.kategoriId,
    this.satuanId,
    this.sku,
    this.barcode,
    required this.nama,
    this.deskripsi,
    this.gambarUrl,
    required this.tipe,
    required this.lacakStok,
    required this.punyaVarian,
    required this.pakaiResep,
    required this.hpp,
    required this.hargaJual,
    required this.dijual,
    required this.aktif,
  });

  final String id;
  final String tokoId;
  final String? kategoriId;
  final String? satuanId;
  final String? sku;
  final String? barcode;
  final String nama;
  final String? deskripsi;
  final String? gambarUrl;
  final ProdukTipe tipe;
  final bool lacakStok;
  final bool punyaVarian;
  final bool pakaiResep;
  final int hpp;
  final int hargaJual;
  final bool dijual;
  final bool aktif;
}
