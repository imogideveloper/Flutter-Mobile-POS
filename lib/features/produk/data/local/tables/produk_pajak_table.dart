import 'package:drift/drift.dart';

import '../../../../promo/data/local/tables/pajak_table.dart';
import 'produk_table.dart';

@DataClassName('ProdukPajakRow')
class ProdukPajak extends Table {
  @override
  String get tableName => 'produk_pajak';

  TextColumn get produkId => text().references(Produk, #id)();
  TextColumn get pajakId => text().references(Pajak, #id)();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {produkId, pajakId};
}
