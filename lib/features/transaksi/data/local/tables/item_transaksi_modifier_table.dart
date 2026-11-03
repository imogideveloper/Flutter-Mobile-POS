import 'package:drift/drift.dart';

import '../../../../produk/data/local/tables/modifier_table.dart';
import 'item_transaksi_table.dart';

@DataClassName('ItemTransaksiModifierRow')
class ItemTransaksiModifier extends Table {
  @override
  String get tableName => 'item_transaksi_modifier';

  TextColumn get id => text()();
  TextColumn get itemTransaksiId => text().references(ItemTransaksi, #id)();
  TextColumn get modifierId => text().nullable().references(Modifier, #id)();
  TextColumn get nama => text()();
  IntColumn get harga => integer().withDefault(const Constant(0))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
