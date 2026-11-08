/// Satu pilihan tambahan pada sebuah item (dokumen IMOGI no. 42, "Varian &
/// tambahan produk": ukuran, level gula/pedas, topping berbayar). Disalin
/// dari modifier saat dipilih kasir, supaya struk dan riwayat tetap benar
/// walau modifier diubah atau dihapus kemudian.
class ModifierPilihan {
  const ModifierPilihan({this.modifierId, required this.nama, this.harga = 0});

  /// null = tambahan yang id modifier-nya tidak diketahui (data lama).
  final String? modifierId;
  final String nama;

  /// Harga tambahan per unit item, Rupiah (0 = gratis, mis. level gula).
  final int harga;

  @override
  bool operator ==(Object other) =>
      other is ModifierPilihan && other.modifierId == modifierId && other.nama == nama && other.harga == harga;

  @override
  int get hashCode => Object.hash(modifierId, nama, harga);
}

class ItemKeranjang {
  const ItemKeranjang({
    required this.produkId,
    required this.namaProduk,
    required this.hargaSatuan,
    required this.qty,
    required this.lacakStok,
    this.modifiers = const [],
  });

  final String produkId;
  final String namaProduk;

  /// Harga DASAR per unit (tanpa tambahan). Harga akhir per unit =
  /// [hargaSatuanFinal].
  final int hargaSatuan;
  final double qty;
  final bool lacakStok;
  final List<ModifierPilihan> modifiers;

  int get tambahanModifier => modifiers.fold<int>(0, (sum, m) => sum + m.harga);

  /// Harga per unit termasuk semua tambahan.
  int get hargaSatuanFinal => hargaSatuan + tambahanModifier;

  int get subtotal => (hargaSatuanFinal * qty).round();

  /// Kunci baris di keranjang: produk yang sama dengan pilihan tambahan
  /// berbeda (mis. Es Kopi Large vs Regular) adalah DUA baris terpisah.
  /// Produk tanpa tambahan memakai produkId apa adanya (perilaku lama).
  String get kunciBaris {
    if (modifiers.isEmpty) return produkId;
    final ids = [for (final m in modifiers) m.modifierId ?? m.nama]..sort();
    return '$produkId|${ids.join(',')}';
  }

  ItemKeranjang copyWith({double? qty}) => ItemKeranjang(
        produkId: produkId,
        namaProduk: namaProduk,
        hargaSatuan: hargaSatuan,
        qty: qty ?? this.qty,
        lacakStok: lacakStok,
        modifiers: modifiers,
      );
}
