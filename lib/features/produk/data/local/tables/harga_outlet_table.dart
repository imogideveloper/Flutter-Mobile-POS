import 'package:drift/drift.dart';

import '../../../../../core/database/tables/outlets_table.dart';
import 'produk_table.dart';
import 'produk_varian_table.dart';

@DataClassName('HargaOutletRow')
class HargaOutlet extends Table {
  @override
  String get tableName => 'harga_outlet';

  TextColumn get id => text()();
  TextColumn get outletId => text().references(Outlets, #id)();
  TextColumn get produkId => text().references(Produk, #id)();
  TextColumn get varianId => text().nullable().references(ProdukVarian, #id)();
  IntColumn get hargaJual => integer()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
        {outletId, produkId, varianId},
      ];
}
