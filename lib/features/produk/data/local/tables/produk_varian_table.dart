import 'package:drift/drift.dart';

import 'produk_table.dart';

@DataClassName('ProdukVarianRow')
class ProdukVarian extends Table {
  @override
  String get tableName => 'produk_varian';

  TextColumn get id => text()();
  TextColumn get produkId => text().references(Produk, #id)();
  TextColumn get nama => text()();
  TextColumn get sku => text().nullable()();
  TextColumn get barcode => text().nullable()();
  IntColumn get hpp => integer().withDefault(const Constant(0))();
  IntColumn get hargaJual => integer().withDefault(const Constant(0))();
  BoolColumn get aktif => boolean().withDefault(const Constant(true))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
