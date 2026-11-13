import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/database_provider.dart';
import '../../data/local/stok_dao.dart';
import '../../data/stok_repository.dart';
import '../../domain/mutasi_item.dart';
import '../../domain/stok_item.dart';

final stokDaoProvider = Provider<StokDao>((ref) {
  return ref.watch(appDatabaseProvider).stokDao;
});

final stokRepositoryProvider = Provider<StokRepository>((ref) {
  return StokRepository(ref.watch(stokDaoProvider));
});

final stokOutletProvider =
    StreamProvider.family<List<StokItem>, String>((ref, outletId) {
  return ref.watch(stokRepositoryProvider).watchStokOutlet(outletId);
});

final mutasiTerakhirProvider =
    StreamProvider.family<List<MutasiItem>, String>((ref, outletId) {
  return ref.watch(stokRepositoryProvider).watchMutasiTerakhir(outletId);
});

/// Riwayat mutasi satu produk: kunci = (outletId, produkId).
final riwayatMutasiProdukProvider =
    StreamProvider.family<List<MutasiItem>, (String, String)>((ref, kunci) {
  return ref.watch(stokRepositoryProvider).watchMutasiProduk(kunci.$1, kunci.$2);
});
