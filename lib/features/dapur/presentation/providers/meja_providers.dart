import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/database_provider.dart';
import '../../../../core/providers/session_provider.dart';
import '../../data/local/meja_dao.dart';
import '../../domain/meja.dart';
import '../../domain/meja_mapper.dart';

final mejaDaoProvider = Provider<MejaDao>((ref) {
  return ref.watch(appDatabaseProvider).mejaDao;
});

final mejaAktifProvider = StreamProvider<List<Meja>>((ref) {
  final outletId = ref.watch(currentOutletIdProvider);
  return ref.watch(mejaDaoProvider).watchMejaAktif(outletId).map(
        (rows) => rows.map((row) => row.toDomain()).toList(),
      );
});
