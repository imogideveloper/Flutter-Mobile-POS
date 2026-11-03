import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/seed.dart';
import 'database_provider.dart';

/// Dipanggil sebelum LoginPage menampilkan daftar pengguna - tanpa ini,
/// instalasi pertama akan menampilkan daftar pengguna kosong karena
/// IzinService baru men-seed secara lazy saat ada aksi sensitif (yang
/// tidak pernah terjadi sebelum ada yang login sama sekali).
final seedProvider = FutureProvider<void>((ref) async {
  final db = ref.watch(appDatabaseProvider);
  await seedRoleDanOwner(db);
  await seedTipeOrderDefault(db);
  await seedMetodeBayarDefault(db);
});
