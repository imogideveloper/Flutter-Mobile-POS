import 'package:drift/drift.dart';

import '../../../../pelanggan/data/local/tables/pelanggan_table.dart';
import '../../../../transaksi/data/local/tables/transaksi_table.dart';
import 'survei_table.dart';

@DataClassName('JawabanSurveiRow')
class JawabanSurvei extends Table {
  @override
  String get tableName => 'jawaban_survei';

  TextColumn get id => text()();
  TextColumn get surveiId => text().references(Survei, #id)();
  TextColumn get transaksiId => text().nullable().references(Transaksi, #id)();
  TextColumn get pelangganId => text().nullable().references(Pelanggan, #id)();
  IntColumn get dijawabPada => integer()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
