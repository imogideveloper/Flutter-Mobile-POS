import 'package:drift/drift.dart';

import 'outlets_table.dart';

@DataClassName('PerangkatRow')
class Perangkat extends Table {
  @override
  String get tableName => 'perangkat';

  TextColumn get id => text()();
  TextColumn get tokoId => text()();
  TextColumn get outletId => text().nullable().references(Outlets, #id)();
  TextColumn get nama => text()();
  TextColumn get deviceUid => text()();
  TextColumn get platform => text().nullable()();
  TextColumn get versiApp => text().nullable()();
  TextColumn get fcmToken => text().nullable()();
  IntColumn get terakhirSync => integer().nullable()();
  BoolColumn get aktif => boolean().withDefault(const Constant(true))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
        {tokoId, deviceUid},
      ];
}
