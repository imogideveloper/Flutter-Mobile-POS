import 'package:drift/drift.dart';

import 'item_transaksi_table.dart';
import 'refund_table.dart';

@DataClassName('ItemRefundRow')
class ItemRefund extends Table {
  @override
  String get tableName => 'item_refund';

  TextColumn get id => text()();
  TextColumn get refundId => text().references(Refund, #id)();
  TextColumn get itemTransaksiId => text().references(ItemTransaksi, #id)();
  RealColumn get qty => real()();
  IntColumn get jumlah => integer()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
