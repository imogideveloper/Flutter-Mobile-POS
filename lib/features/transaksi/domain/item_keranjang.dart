/// Baris di keranjang belanja - state transien sebelum transaksi disimpan.
class ItemKeranjang {
  const ItemKeranjang({
    required this.produkId,
    required this.namaProduk,
    required this.hargaSatuan,
    required this.qty,
    required this.lacakStok,
  });

  final String produkId;
  final String namaProduk;
  final int hargaSatuan;
  final double qty;

  /// Disalin dari Produk.lacakStok saat ditambahkan - dipakai saat checkout
  /// untuk tahu item mana yang harus ikut mendebet saldo stok (produk jasa
  /// biasanya tidak).
  final bool lacakStok;

  int get subtotal => (hargaSatuan * qty).round();

  ItemKeranjang copyWith({double? qty}) => ItemKeranjang(
        produkId: produkId,
        namaProduk: namaProduk,
        hargaSatuan: hargaSatuan,
        qty: qty ?? this.qty,
        lacakStok: lacakStok,
      );
}
