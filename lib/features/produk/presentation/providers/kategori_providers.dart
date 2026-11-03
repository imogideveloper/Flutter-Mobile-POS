import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/kategori.dart';
import '../../data/kategori_repository.dart';
import 'produk_providers.dart' show produkDaoProvider;

final kategoriRepositoryProvider = Provider<KategoriRepository>((ref) {
  return KategoriRepository(ref.watch(produkDaoProvider));
});

final kategoriAktifProvider = StreamProvider.family<List<Kategori>, String>((ref, tokoId) {
  return ref.watch(kategoriRepositoryProvider).watchKategoriAktif(tokoId);
});
