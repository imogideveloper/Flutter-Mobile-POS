import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/izin_service.dart';
import 'database_provider.dart';
import 'session_provider.dart';

final izinServiceProvider = Provider<IzinService>((ref) {
  return IzinService(ref.watch(appDatabaseProvider));
});

/// Kode izin milik pengguna yang sedang login. Belum login = himpunan kosong (tidak ada akses).
final izinSayaProvider = FutureProvider<Set<String>>((ref) async {
  final penggunaId = ref.watch(currentPenggunaIdProvider);
  if (penggunaId == null) return <String>{};
  return ref.watch(izinServiceProvider).daftarIzin(penggunaId);
});
