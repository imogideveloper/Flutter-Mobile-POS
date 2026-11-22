import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/toko_profile_provider.dart';
import '../../../core/struk/penyusun_label_produk.dart';
import '../../../core/struk/penyusun_tiket_dapur.dart';
import '../../produk/presentation/providers/produk_providers.dart'
    show produkDaoProvider;
import '../../transaksi/domain/item_keranjang.dart';

/// Item untuk tiket dapur: semua item KECUALI yang kategorinya dimatikan
/// ("Masuk tiket dapur" di form kategori). Daftar kosong berarti tidak ada
/// yang perlu dicetak ke dapur.
Future<List<ItemTiketDapur>> itemUntukTiketDapur(
  WidgetRef ref,
  List<ItemKeranjang> items,
) async {
  final dikecualikan = await ref.read(produkDaoProvider).produkTanpaTiketDapur([
    for (final i in items) i.produkId,
  ]);
  return [
    for (final i in items)
      if (!dikecualikan.contains(i.produkId))
        ItemTiketDapur(
          namaProduk: i.namaProduk,
          qty: i.qty,
          tambahan: [for (final m in i.modifiers) m.nama],
        ),
  ];
}

/// Satu tiket: [stasiun] null = tiket umum (kategori tanpa stasiun).
class TiketPerStasiun {
  const TiketPerStasiun({required this.stasiun, required this.items});

  final String? stasiun;
  final List<ItemTiketDapur> items;
}

/// Kelompokkan item per stasiun dapur (IMOGI no. 35) mengikuti urutan kemunculan pertama, sehingga satu
/// pesanan menghasilkan satu tiket per stasiun (mis. Bar dan Dapur), bukan satu tiket campur.
/// FUNGSI MURNI: [stasiunDari] memetakan produkId -> nama stasiun (tidak ada = tiket umum).
List<TiketPerStasiun> kelompokkanPerStasiun(
  List<({String produkId, ItemTiketDapur item})> items,
  Map<String, String> stasiunDari,
) {
  final urutan = <String?>[];
  final grup = <String?, List<ItemTiketDapur>>{};
  for (final e in items) {
    final s = stasiunDari[e.produkId];
    if (!grup.containsKey(s)) urutan.add(s);
    grup.putIfAbsent(s, () => []).add(e.item);
  }
  return [for (final s in urutan) TiketPerStasiun(stasiun: s, items: grup[s]!)];
}

/// Tiket yang perlu dicetak untuk [items]: kategori yang dimatikan dari tiket dibuang, sisanya dibagi per
/// stasiun. Daftar kosong = tidak ada yang perlu dicetak.
Future<List<TiketPerStasiun>> tiketUntukDicetak(
  WidgetRef ref,
  List<ItemKeranjang> items,
) async {
  final dikecualikan = await ref.read(produkDaoProvider).produkTanpaTiketDapur([
    for (final i in items) i.produkId,
  ]);
  final dipakai = [
    for (final i in items)
      if (!dikecualikan.contains(i.produkId)) i,
  ];
  if (dipakai.isEmpty) return const [];
  final stasiun = await ref.read(produkDaoProvider).namaStasiunPerProduk([
    for (final i in dipakai) i.produkId,
  ]);
  return kelompokkanPerStasiun([
    for (final i in dipakai)
      (
        produkId: i.produkId,
        item: ItemTiketDapur(
          namaProduk: i.namaProduk,
          qty: i.qty,
          tambahan: [for (final m in i.modifiers) m.nama],
        ),
      ),
  ], stasiun);
}

/// Label kemasan untuk [items]: item yang kategorinya dimatikan dari tiket dapur tidak ikut (minuman kemasan
/// jadi, dsb. tidak perlu stiker), sisanya satu label per porsi. Kosong = tidak ada yang perlu dicetak.
Future<List<LabelProdukData>> labelUntukDicetak(
  WidgetRef ref,
  List<ItemKeranjang> items, {
  required int tanggalEpochMs,
  String? nomorAntrean,
  String? nomorStruk,
}) async {
  final tiket = await tiketUntukDicetak(ref, items);
  final namaToko = (await ref.read(tokoProfileProvider.future))?.namaToko;
  return susunLabelProduk(
    items: [for (final t in tiket) ...t.items],
    tanggalEpochMs: tanggalEpochMs,
    nomorAntrean: nomorAntrean,
    nomorStruk: nomorStruk,
    namaToko: namaToko,
  );
}
