import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/struk/penyusun_tiket_dapur.dart';
import '../../produk/presentation/providers/produk_providers.dart' show produkDaoProvider;
import '../../transaksi/domain/item_keranjang.dart';

/// Item untuk tiket dapur: semua item KECUALI yang kategorinya dimatikan
/// ("Masuk tiket dapur" di form kategori). Daftar kosong berarti tidak ada
/// yang perlu dicetak ke dapur.
Future<List<ItemTiketDapur>> itemUntukTiketDapur(WidgetRef ref, List<ItemKeranjang> items) async {
  final dikecualikan = await ref.read(produkDaoProvider).produkTanpaTiketDapur([for (final i in items) i.produkId]);
  return [
    for (final i in items)
      if (!dikecualikan.contains(i.produkId))
        ItemTiketDapur(namaProduk: i.namaProduk, qty: i.qty, tambahan: [for (final m in i.modifiers) m.nama]),
  ];
}
