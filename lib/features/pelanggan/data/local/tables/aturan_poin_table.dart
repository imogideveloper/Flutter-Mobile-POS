import 'package:drift/drift.dart';

/// PK = tokoId sendiri (satu baris aturan per toko), bukan id terpisah -
/// sama seperti skema Postgres.
@DataClassName('AturanPoinRow')
class AturanPoin extends Table {
  @override
  String get tableName => 'aturan_poin';

  TextColumn get tokoId => text()();
  IntColumn get nominalPerPoin => integer().withDefault(const Constant(10000))();
  IntColumn get nilaiTukarPoin => integer().withDefault(const Constant(100))();
  IntColumn get minTukarPoin => integer().withDefault(const Constant(0))();
  IntColumn get kedaluwarsaHari => integer().nullable()();
  BoolColumn get aktif => boolean().withDefault(const Constant(true))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {tokoId};
}
