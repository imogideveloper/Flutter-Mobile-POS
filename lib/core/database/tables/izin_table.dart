import 'package:drift/drift.dart';

@DataClassName('IzinRow')
class Izin extends Table {
  @override
  String get tableName => 'izin';

  TextColumn get id => text()();
  TextColumn get kode => text().unique()();
  TextColumn get modul => text()();
  TextColumn get deskripsi => text().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
