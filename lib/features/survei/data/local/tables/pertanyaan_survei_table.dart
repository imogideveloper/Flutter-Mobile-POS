import 'package:drift/drift.dart';

import 'survei_table.dart';

enum PertanyaanSurveiTipe { rating, pilihan, teks }

@DataClassName('PertanyaanSurveiRow')
class PertanyaanSurvei extends Table {
  @override
  String get tableName => 'pertanyaan_survei';

  TextColumn get id => text()();
  TextColumn get surveiId => text().references(Survei, #id)();
  TextColumn get teks => text()();
  TextColumn get tipe => textEnum<PertanyaanSurveiTipe>()();
  // jsonb di Postgres - disimpan sebagai teks JSON mentah, diparse manual.
  TextColumn get opsi => text().nullable()();
  BoolColumn get wajib => boolean().withDefault(const Constant(false))();
  IntColumn get urutan => integer().withDefault(const Constant(0))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
