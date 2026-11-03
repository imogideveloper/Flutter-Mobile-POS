import 'package:drift/drift.dart';

import '../../../../../core/database/tables/pengguna_table.dart';
import '../../../../produk/data/local/tables/produk_table.dart';
import '../../../../produk/data/local/tables/produk_varian_table.dart';
import 'transaksi_table.dart';

/// namaProduk, hargaSatuan, hppSatuan adalah snapshot saat transaksi dibuat -
/// tidak boleh ikut berubah walau master produk diubah setelahnya, supaya
/// struk lama tetap konsisten dengan yang dicetak.
@DataClassName('ItemTransaksiRow')
class ItemTransaksi extends Table {
  @override
  String get tableName => 'item_transaksi';

  TextColumn get id => text()();
  TextColumn get transaksiId => text().references(Transaksi, #id)();
  TextColumn get produkId => text().references(Produk, #id)();
  TextColumn get varianId => text().nullable().references(ProdukVarian, #id)();
  // Staf yang mengerjakan (relevan untuk usaha jasa, mis. laundry/salon).
  TextColumn get stafId => text().nullable().references(Pengguna, #id)();
  TextColumn get namaProduk => text()();
  RealColumn get qty => real()();
  IntColumn get hargaSatuan => integer()();
  IntColumn get hppSatuan => integer().withDefault(const Constant(0))();
  IntColumn get diskon => integer().withDefault(const Constant(0))();
  IntColumn get subtotal => integer()();
  TextColumn get catatan => text().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
