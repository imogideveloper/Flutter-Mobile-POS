import 'package:drift/drift.dart';

import '../../../../transaksi/data/local/tables/item_transaksi_table.dart';
import 'pesanan_dapur_table.dart';

@DataClassName('ItemPesananDapurRow')
class ItemPesananDapur extends Table {
  @override
  String get tableName => 'item_pesanan_dapur';

  TextColumn get id => text()();
  TextColumn get pesananDapurId => text().references(PesananDapur, #id)();
  TextColumn get itemTransaksiId => text().references(ItemTransaksi, #id)();
  RealColumn get qty => real()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
