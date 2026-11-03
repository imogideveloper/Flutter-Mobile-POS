import 'package:drift/drift.dart';

import '../../../../produk/data/local/tables/produk_table.dart';
import 'promo_table.dart';

@DataClassName('PromoProdukRow')
class PromoProduk extends Table {
  @override
  String get tableName => 'promo_produk';

  TextColumn get promoId => text().references(Promo, #id)();
  TextColumn get produkId => text().references(Produk, #id)();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {promoId, produkId};
}
