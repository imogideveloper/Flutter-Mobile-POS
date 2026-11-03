import 'package:drift/drift.dart';

import 'produk_table.dart';
import 'produk_varian_table.dart';

/// bundling_produk_id <> produk_id divalidasi di domain layer, sama pola
/// dengan check constraint lain yang tidak portable (lihat resep_table.dart).
@DataClassName('BundlingItemRow')
class BundlingItem extends Table {
  @override
  String get tableName => 'bundling_item';

  TextColumn get id => text()();
  TextColumn get bundlingProdukId => text().references(Produk, #id)();
  TextColumn get produkId => text().references(Produk, #id)();
  TextColumn get varianId => text().nullable().references(ProdukVarian, #id)();
  RealColumn get qty => real()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
