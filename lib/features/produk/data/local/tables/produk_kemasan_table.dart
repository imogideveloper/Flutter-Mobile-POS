import 'package:drift/drift.dart';

/// Kemasan jual sebuah produk (IMOGI no. 43): mis. 1 dus = 12 pcs dengan harga sendiri.
/// Stok tetap di satuan dasar produk; [isi] = jumlah satuan dasar per kemasan.
@DataClassName('ProdukKemasanRow')
class ProdukKemasan extends Table {
  @override
  String get tableName => 'produk_kemasan';

  TextColumn get id => text()();
  TextColumn get tokoId => text()();
  TextColumn get produkId => text()();
  TextColumn get nama => text()();
  RealColumn get isi => real()();
  IntColumn get harga => integer()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
