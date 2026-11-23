import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/database_provider.dart';
import '../../../../core/providers/session_provider.dart';
import '../../data/local/pelanggan_dao.dart';
import '../../data/pelanggan_repository.dart';
import '../../domain/pelanggan.dart';
import '../../domain/pelanggan_mapper.dart';

final pelangganDaoProvider = Provider<PelangganDao>((ref) {
  return ref.watch(appDatabaseProvider).pelangganDao;
});

final pelangganRepositoryProvider = Provider<PelangganRepository>((ref) {
  return PelangganRepository(ref.watch(pelangganDaoProvider));
});

final pelangganAktifProvider = StreamProvider<List<Pelanggan>>((ref) {
  final tokoId = ref.watch(currentTokoIdProvider);
  return ref.watch(pelangganRepositoryProvider).watchPelangganAktif(tokoId);
});

/// Aturan poin toko saat ini, dibaca SEKALI langsung dari basis data. Dipakai aksi sesaat (mis. tombol
/// Tukar poin): `await ref.read(aturanPoinProvider.future)` tidak pernah selesai di HP maupun di tes
/// (ditemukan 2026-11-23: tombol Tukar poin diam saja), jadi aksi tidak boleh menunggu future provider itu.
Future<AturanPoin?> muatAturanPoinSekarang(WidgetRef ref) async {
  final row = await ref.read(pelangganDaoProvider).watchAturanPoin(ref.read(currentTokoIdProvider)).first;
  return row?.toDomain();
}

final pelangganByIdProvider = FutureProvider.family<String?, String>((ref, id) async {
  final row = await ref.watch(pelangganDaoProvider).pelangganById(id);
  return row?.nama;
});

final levelMemberProvider = StreamProvider<List<LevelMember>>((ref) {
  final tokoId = ref.watch(currentTokoIdProvider);
  return ref.watch(pelangganRepositoryProvider).watchLevelMember(tokoId);
});

/// null = toko belum pernah mengatur aturan poin (tampilkan default form
/// kosong, BUKAN error) - lihat PelangganDao.watchAturanPoin.
final aturanPoinProvider = StreamProvider<AturanPoin?>((ref) {
  final tokoId = ref.watch(currentTokoIdProvider);
  return ref.watch(pelangganDaoProvider).watchAturanPoin(tokoId).map(
        (row) => row?.toDomain(),
      );
});
