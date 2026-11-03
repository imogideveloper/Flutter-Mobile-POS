import 'package:drift/drift.dart';

import '../../../../transaksi/data/local/tables/transaksi_table.dart';
import 'stasiun_dapur_table.dart';

enum PesananDapurStatus { baru, dimasak, siap, disajikan, dibatalkan }

/// Satu transaksi bisa punya lebih dari satu tiket dapur (urutanKirim 1, 2,
/// ... untuk pesan tambahan di tengah makan).
@DataClassName('PesananDapurRow')
class PesananDapur extends Table {
  @override
  String get tableName => 'pesanan_dapur';

  TextColumn get id => text()();
  TextColumn get transaksiId => text().references(Transaksi, #id)();
  TextColumn get stasiunDapurId => text().nullable().references(StasiunDapur, #id)();
  IntColumn get urutanKirim => integer().withDefault(const Constant(1))();
  TextColumn get status =>
      textEnum<PesananDapurStatus>().withDefault(const Constant('baru'))();
  IntColumn get dicetakPada => integer().nullable()();
  IntColumn get siapPada => integer().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
