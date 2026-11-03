import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/database_provider.dart';
import '../../data/local/pajak_dao.dart';
import '../../data/pajak_repository.dart';
import '../../domain/pajak.dart';

final pajakDaoProvider = Provider<PajakDao>((ref) {
  return ref.watch(appDatabaseProvider).pajakDao;
});

final pajakRepositoryProvider = Provider<PajakRepository>((ref) {
  return PajakRepository(ref.watch(pajakDaoProvider));
});

final pajakAktifProvider = StreamProvider.family<List<Pajak>, String>((ref, tokoId) {
  return ref.watch(pajakRepositoryProvider).watchPajakAktif(tokoId);
});
