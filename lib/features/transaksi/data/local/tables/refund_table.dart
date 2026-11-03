import 'package:drift/drift.dart';

import '../../../../../core/database/tables/pengguna_table.dart';
import '../../../../shift/data/local/tables/shift_table.dart';
import 'metode_bayar_table.dart';
import 'transaksi_table.dart';

@DataClassName('RefundRow')
class Refund extends Table {
  @override
  String get tableName => 'refund';

  TextColumn get id => text()();
  TextColumn get transaksiId => text().references(Transaksi, #id)();
  TextColumn get shiftId => text().nullable().references(Shift, #id)();
  TextColumn get metodeBayarId => text().nullable().references(MetodeBayar, #id)();
  TextColumn get nomor => text()();
  TextColumn get alasan => text()();
  IntColumn get total => integer()();
  BoolColumn get kembalikanStok => boolean().withDefault(const Constant(true))();
  TextColumn get dibuatOleh => text().nullable().references(Pengguna, #id)();
  TextColumn get disetujuiOleh => text().nullable().references(Pengguna, #id)();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
