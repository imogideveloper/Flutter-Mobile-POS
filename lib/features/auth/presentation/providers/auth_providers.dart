import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/pairing_dao.dart';
import '../../../../core/database/pengguna_dao.dart';
import '../../../../core/providers/database_provider.dart';
import '../../data/pengguna_repository.dart';
import '../../domain/pengguna.dart';

final penggunaDaoProvider = Provider<PenggunaDao>((ref) {
  return ref.watch(appDatabaseProvider).penggunaDao;
});

final pairingDaoProvider = Provider<PairingDao>((ref) {
  return ref.watch(appDatabaseProvider).pairingDao;
});

final penggunaRepositoryProvider = Provider<PenggunaRepository>((ref) {
  return PenggunaRepository(ref.watch(penggunaDaoProvider));
});

final penggunaAktifProvider = StreamProvider.family<List<Pengguna>, String>((ref, tokoId) {
  return ref.watch(penggunaRepositoryProvider).watchPenggunaAktif(tokoId);
});

final roleBawaanProvider = StreamProvider<List<RoleRow>>((ref) {
  return ref.watch(penggunaRepositoryProvider).watchRoleBawaan();
});
