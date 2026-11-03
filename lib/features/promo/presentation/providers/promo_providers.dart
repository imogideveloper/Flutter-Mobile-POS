import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/database_provider.dart';
import '../../../../core/providers/session_provider.dart';
import '../../data/local/promo_dao.dart';
import '../../data/promo_repository.dart';
import '../../domain/promo.dart';

final promoDaoProvider = Provider<PromoDao>((ref) {
  return ref.watch(appDatabaseProvider).promoDao;
});

final promoRepositoryProvider = Provider<PromoRepository>((ref) {
  return PromoRepository(ref.watch(promoDaoProvider));
});

final promoAktifProvider = StreamProvider<List<Promo>>((ref) {
  final tokoId = ref.watch(currentTokoIdProvider);
  return ref.watch(promoRepositoryProvider).watchPromoAktif(tokoId);
});
