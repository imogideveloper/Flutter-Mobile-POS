import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import 'tables/satuan_table.dart';

part 'satuan_dao.g.dart';

@DriftAccessor(tables: [Satuan])
class SatuanDao extends DatabaseAccessor<AppDatabase> with _$SatuanDaoMixin {
  SatuanDao(super.db);

  Future<void> upsertSatuan(SatuanCompanion data) =>
      into(satuan).insertOnConflictUpdate(data);
}
