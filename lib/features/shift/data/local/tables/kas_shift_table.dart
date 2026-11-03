import 'package:drift/drift.dart';

import '../../../../../core/database/tables/pengguna_table.dart';
import 'shift_table.dart';

enum KasShiftJenis { masuk, keluar }

@DataClassName('KasShiftRow')
class KasShift extends Table {
  @override
  String get tableName => 'kas_shift';

  TextColumn get id => text()();
  TextColumn get shiftId => text().references(Shift, #id)();
  TextColumn get jenis => textEnum<KasShiftJenis>()();
  IntColumn get jumlah => integer()();
  TextColumn get keterangan => text()();
  TextColumn get dibuatOleh => text().nullable().references(Pengguna, #id)();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
