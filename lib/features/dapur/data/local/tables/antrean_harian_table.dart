import 'package:drift/drift.dart';

import '../../../../../core/database/tables/outlets_table.dart';
import '../../../../../core/database/tables/perangkat_table.dart';

/// Saat offline, HP membuat nomor dari penghitung lokalnya sendiri; kalau
/// 2+ HP kasir di satu outlet, prefix per perangkat (A-012, B-007) mencegah
/// bentrok - lihat komentar yang sama di skema Postgres.
@DataClassName('AntreanHarianRow')
class AntreanHarian extends Table {
  @override
  String get tableName => 'antrean_harian';

  TextColumn get outletId => text().references(Outlets, #id)();
  TextColumn get perangkatId => text().references(Perangkat, #id)();
  // date di Postgres - epoch ms UTC tengah malam.
  IntColumn get tanggal => integer()();
  TextColumn get prefix => text().withDefault(const Constant(''))();
  IntColumn get nomorTerakhir => integer().withDefault(const Constant(0))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {outletId, perangkatId, tanggal};
}
