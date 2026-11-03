import 'package:drift/drift.dart';

import '../../../../promo/data/local/tables/pajak_table.dart';
import 'transaksi_table.dart';

/// Snapshot nama+persen+jumlah pajak yang berlaku saat transaksi dibuat -
/// sama alasannya dengan snapshot di ItemTransaksi.
@DataClassName('TransaksiPajakRow')
class TransaksiPajak extends Table {
  @override
  String get tableName => 'transaksi_pajak';

  TextColumn get id => text()();
  TextColumn get transaksiId => text().references(Transaksi, #id)();
  TextColumn get pajakId => text().nullable().references(Pajak, #id)();
  TextColumn get nama => text()();
  RealColumn get persen => real()();
  IntColumn get jumlah => integer()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
