import 'package:drift/drift.dart';

import '../../../../../core/database/tables/outlets_table.dart';
import '../../../../produk/data/local/tables/produk_table.dart';
import '../../../../produk/data/local/tables/produk_varian_table.dart';

/// Saldo terkini saja - sumber kebenaran ada di MutasiStok. Unique index di
/// bawah ini TIDAK meniru "NULLS NOT DISTINCT" Postgres (SQLite menganggap
/// NULL selalu berbeda), jadi upsert saldo WAJIB lewat StokDao.upsertSaldo
/// yang query manual by (outletId, produkId, varianId) termasuk kasus
/// varianId NULL, bukan mengandalkan constraint ini untuk mencegah duplikat.
@DataClassName('StokRow')
class Stok extends Table {
  @override
  String get tableName => 'stok';

  TextColumn get id => text()();
  TextColumn get outletId => text().references(Outlets, #id)();
  TextColumn get produkId => text().references(Produk, #id)();
  TextColumn get varianId => text().nullable().references(ProdukVarian, #id)();
  RealColumn get jumlah => real().withDefault(const Constant(0))();
  RealColumn get batasMinimum => real().withDefault(const Constant(0))();
  IntColumn get hppRataRata => integer().withDefault(const Constant(0))();
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
