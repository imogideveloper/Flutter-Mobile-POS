import 'package:drift/drift.dart';

/// Cache read-only hasil pull dari server - app tidak pernah menulis ke
/// tabel ini, cuma query lewat featureGate.has(kode).
@DataClassName('FiturRow')
class Fitur extends Table {
  @override
  String get tableName => 'fitur';

  TextColumn get id => text()();
  TextColumn get kode => text().unique()();
  TextColumn get nama => text()();
  TextColumn get modul => text()();
  IntColumn get tingkat => integer().withDefault(const Constant(0))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
