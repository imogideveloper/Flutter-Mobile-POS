import 'package:drift/drift.dart';

@DataClassName('SatuanRow')
class Satuan extends Table {
  @override
  String get tableName => 'satuan';

  TextColumn get id => text()();
  TextColumn get tokoId => text()();
  TextColumn get nama => text()();
  TextColumn get singkatan => text()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
