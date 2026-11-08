import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/database_provider.dart';
import '../../data/local/produk_dao.dart';
import '../../data/produk_repository.dart';
import '../../domain/grup_tambahan.dart';
import '../../domain/produk.dart';

final produkDaoProvider = Provider<ProdukDao>((ref) {
  return ref.watch(appDatabaseProvider).produkDao;
});

final produkRepositoryProvider = Provider<ProdukRepository>((ref) {
  return ProdukRepository(ref.watch(produkDaoProvider));
});

final produkAktifProvider = StreamProvider<List<Produk>>((ref) {
  return ref.watch(produkRepositoryProvider).watchProdukAktif();
});

final produkSemuaProvider = StreamProvider<List<Produk>>((ref) {
  return ref.watch(produkRepositoryProvider).watchProdukSemua();
});

/// Grup varian/tambahan (beserta opsi aktif) milik satu produk. Kosong bila
/// produk tidak punya tambahan - kasir lalu menambah langsung tanpa pemilih.
final grupTambahanProdukProvider = FutureProvider.autoDispose.family<List<GrupTambahan>, String>((ref, produkId) {
  return ref.watch(produkDaoProvider).grupUntukProduk(produkId);
});
