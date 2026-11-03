import 'package:drift/drift.dart';

import '../../../../../core/database/tables/outlets_table.dart';

@DataClassName('MejaRow')
class Meja extends Table {
  @override
  String get tableName => 'meja';

  TextColumn get id => text()();
  TextColumn get outletId => text().references(Outlets, #id)();
  TextColumn get nama => text()();
  TextColumn get area => text().nullable()();
  IntColumn get kapasitas => integer().nullable()();
  IntColumn get urutan => integer().withDefault(const Constant(0))();
  BoolColumn get aktif => boolean().withDefault(const Constant(true))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
        {outletId, nama},
      ];
}
