import 'package:drift/drift.dart';

import '../../../../promo/data/local/tables/pajak_table.dart';
import 'tipe_order_table.dart';

@DataClassName('TipeOrderPajakRow')
class TipeOrderPajak extends Table {
  @override
  String get tableName => 'tipe_order_pajak';

  TextColumn get tipeOrderId => text().references(TipeOrder, #id)();
  TextColumn get pajakId => text().references(Pajak, #id)();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {tipeOrderId, pajakId};
}
