import 'package:drift/drift.dart';

enum MetodeBayarTipe { tunai, qris, kartu, transfer, ewallet, lainnya }

@DataClassName('MetodeBayarRow')
class MetodeBayar extends Table {
  @override
  String get tableName => 'metode_bayar';

  TextColumn get id => text()();
  TextColumn get tokoId => text()();
  TextColumn get nama => text()();
  TextColumn get tipe => textEnum<MetodeBayarTipe>()();
  BoolColumn get butuhGateway => boolean().withDefault(const Constant(false))();
  BoolColumn get masukLaci => boolean().withDefault(const Constant(false))();
  IntColumn get urutan => integer().withDefault(const Constant(0))();
  BoolColumn get aktif => boolean().withDefault(const Constant(true))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
