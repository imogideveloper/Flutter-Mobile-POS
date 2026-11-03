import 'package:drift/drift.dart';

import '../../../../../core/database/tables/outlets_table.dart';
import 'produk_table.dart';
import 'produk_varian_table.dart';

/// uniqueKeys di bawah TIDAK meniru "NULLS NOT DISTINCT" Postgres (SQLite
/// menganggap tiap NULL berbeda) - sama risiko yang sudah ditandai di
/// StokTable/HargaOutletTable. Belum ada DAO/repository untuk tabel ini,
/// jadi belum ada query-then-upsert manual seperti StokDao.catatMutasi;
/// wajib dibuat begitu CRUD harga grosir mulai dikerjakan.
@DataClassName('HargaGrosirRow')
class HargaGrosir extends Table {
  @override
  String get tableName => 'harga_grosir';

  TextColumn get id => text()();
  TextColumn get produkId => text().references(Produk, #id)();
  TextColumn get varianId => text().nullable().references(ProdukVarian, #id)();
  TextColumn get outletId => text().nullable().references(Outlets, #id)();
  RealColumn get minQty => real()();
  IntColumn get harga => integer()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
        {produkId, varianId, outletId, minQty},
      ];
}
