import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/izin_service.dart';
import 'database_provider.dart';

final izinServiceProvider = Provider<IzinService>((ref) {
  return IzinService(ref.watch(appDatabaseProvider));
});
