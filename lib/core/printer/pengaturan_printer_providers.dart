import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart';
import '../database/pengaturan_printer_dao.dart';
import '../providers/database_provider.dart';

final pengaturanPrinterDaoProvider = Provider<PengaturanPrinterDao>((ref) {
  return ref.watch(appDatabaseProvider).pengaturanPrinterDao;
});

final pengaturanPrinterProvider = StreamProvider<PengaturanPrinterRow?>((ref) {
  return ref.watch(pengaturanPrinterDaoProvider).watch();
});
