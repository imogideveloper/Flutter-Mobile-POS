import 'package:drift/drift.dart';

import 'produk_table.dart';
import 'produk_varian_table.dart';

/// qty > 0 divalidasi di domain layer (ResepEntity), bukan di skema -
/// drift tidak punya API check-constraint self-reference yang stabil
/// untuk kasus ini.
@DataClassName('ResepRow')
class Resep extends Table {
  @override
  String get tableName => 'resep';

  TextColumn get id => text()();
  TextColumn get produkId => text().references(Produk, #id)();
  TextColumn get varianId => text().nullable().references(ProdukVarian, #id)();
  TextColumn get bahanId => text().references(Produk, #id)();
  RealColumn get qty => real()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
