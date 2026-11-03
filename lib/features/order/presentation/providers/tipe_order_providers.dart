import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/database_provider.dart';
import '../../../../core/providers/session_provider.dart';
import '../../data/local/tipe_order_dao.dart';
import '../../data/tipe_order_repository.dart';
import '../../domain/tipe_order.dart';

final tipeOrderDaoProvider = Provider<TipeOrderDao>((ref) {
  return ref.watch(appDatabaseProvider).tipeOrderDao;
});

final tipeOrderRepositoryProvider = Provider<TipeOrderRepository>((ref) {
  return TipeOrderRepository(ref.watch(tipeOrderDaoProvider));
});

final tipeOrderAktifProvider = StreamProvider<List<TipeOrder>>((ref) {
  final tokoId = ref.watch(currentTokoIdProvider);
  return ref.watch(tipeOrderRepositoryProvider).watchTipeOrderAktif(tokoId);
});
