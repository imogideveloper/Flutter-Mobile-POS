import 'package:drift/drift.dart';

import 'jawaban_survei_table.dart';
import 'pertanyaan_survei_table.dart';

@DataClassName('ItemJawabanSurveiRow')
class ItemJawabanSurvei extends Table {
  @override
  String get tableName => 'item_jawaban_survei';

  TextColumn get id => text()();
  TextColumn get jawabanSurveiId => text().references(JawabanSurvei, #id)();
  TextColumn get pertanyaanSurveiId => text().references(PertanyaanSurvei, #id)();
  IntColumn get nilaiAngka => integer().nullable()();
  TextColumn get nilaiTeks => text().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
