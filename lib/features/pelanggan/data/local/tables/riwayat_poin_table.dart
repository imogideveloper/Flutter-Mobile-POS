import 'package:drift/drift.dart';

import '../../../../transaksi/data/local/tables/transaksi_table.dart';
import 'pelanggan_table.dart';

@DataClassName('RiwayatPoinRow')
class RiwayatPoin extends Table {
  @override
  String get tableName => 'riwayat_poin';

  TextColumn get id => text()();
  TextColumn get pelangganId => text().references(Pelanggan, #id)();
  TextColumn get transaksiId => text().nullable().references(Transaksi, #id)();
  // + dapat poin, - tukar poin.
  IntColumn get poin => integer()();
  TextColumn get keterangan => text().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
