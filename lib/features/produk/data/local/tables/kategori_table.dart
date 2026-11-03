import 'package:drift/drift.dart';

import '../../../../dapur/data/local/tables/stasiun_dapur_table.dart';

@DataClassName('KategoriRow')
class Kategori extends Table {
  @override
  String get tableName => 'kategori';

  TextColumn get id => text()();
  TextColumn get tokoId => text()();
  TextColumn get nama => text()();
  TextColumn get warna => text().nullable()();
  IntColumn get urutan => integer().withDefault(const Constant(0))();
  TextColumn get stasiunDapurId => text().nullable().references(StasiunDapur, #id)();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
