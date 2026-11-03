import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/database_provider.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/local/shift_dao.dart';
import '../../data/shift_repository.dart';
import '../../domain/shift.dart';

final shiftDaoProvider = Provider<ShiftDao>((ref) {
  return ref.watch(appDatabaseProvider).shiftDao;
});

final shiftRepositoryProvider = Provider<ShiftRepository>((ref) {
  return ShiftRepository(ref.watch(shiftDaoProvider));
});

final shiftTerbukaProvider = FutureProvider.family<Shift?, String>((ref, outletId) {
  return ref.watch(shiftRepositoryProvider).shiftTerbukaDiOutlet(outletId);
});

/// Tahap 5b - rekap shift (kartu shift aktif, nanti rekap tutup shift)
/// wajib menampilkan nama kasir YANG SEBENARNYA sedang bertugas
/// (shift.penggunaId), bukan asumsi "pasti Owner" spt sebelum identitas
/// karyawan disatukan dgn server.
final namaPenggunaProvider = FutureProvider.family<String?, String>((ref, penggunaId) async {
  final pengguna = await ref.watch(penggunaDaoProvider).cariById(penggunaId);
  return pengguna?.nama;
});
