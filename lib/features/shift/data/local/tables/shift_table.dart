import 'package:drift/drift.dart';

import '../../../../../core/database/tables/outlets_table.dart';
import '../../../../../core/database/tables/pengguna_table.dart';
import '../../../../../core/database/tables/perangkat_table.dart';

enum ShiftStatus { buka, tutup }

@DataClassName('ShiftRow')
class Shift extends Table {
  @override
  String get tableName => 'shift';

  TextColumn get id => text()();
  TextColumn get tokoId => text()();
  TextColumn get outletId => text().references(Outlets, #id)();
  TextColumn get perangkatId => text().nullable().references(Perangkat, #id)();
  TextColumn get penggunaId => text().references(Pengguna, #id)();
  IntColumn get dibukaPada => integer()();
  IntColumn get ditutupPada => integer().nullable()();
  IntColumn get modalAwal => integer().withDefault(const Constant(0))();
  IntColumn get kasSeharusnya => integer().nullable()();
  IntColumn get kasAktual => integer().nullable()();
  IntColumn get selisih => integer().nullable()();
  TextColumn get catatan => text().nullable()();
  TextColumn get status => textEnum<ShiftStatus>()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
