import 'package:drift/drift.dart';

import '../../../../promo/data/local/tables/promo_table.dart';
import 'transaksi_table.dart';

@DataClassName('TransaksiPromoRow')
class TransaksiPromo extends Table {
  @override
  String get tableName => 'transaksi_promo';

  TextColumn get id => text()();
  TextColumn get transaksiId => text().references(Transaksi, #id)();
  TextColumn get promoId => text().nullable().references(Promo, #id)();
  TextColumn get nama => text()();
  IntColumn get jumlahDiskon => integer()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
