import 'package:drift/drift.dart';

enum PajakTipe { pajak, service }

@DataClassName('PajakRow')
class Pajak extends Table {
  @override
  String get tableName => 'pajak';

  TextColumn get id => text()();
  TextColumn get tokoId => text()();
  TextColumn get nama => text()();
  TextColumn get tipe => textEnum<PajakTipe>().withDefault(const Constant('pajak'))();
  RealColumn get persen => real()();
  BoolColumn get termasukHarga => boolean().withDefault(const Constant(false))();
  // Service dihitung dulu sebelum pajak - urutan ascending.
  IntColumn get urutan => integer().withDefault(const Constant(0))();
  BoolColumn get aktif => boolean().withDefault(const Constant(true))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
