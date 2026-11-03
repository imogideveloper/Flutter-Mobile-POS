import 'package:drift/drift.dart';

enum TipeOrderKanal { makanDiTempat, bawaPulang, antar, online, langsung }

const tipeOrderKanalPostgresValue = <TipeOrderKanal, String>{
  TipeOrderKanal.makanDiTempat: 'makan_di_tempat',
  TipeOrderKanal.bawaPulang: 'bawa_pulang',
  TipeOrderKanal.antar: 'antar',
  TipeOrderKanal.online: 'online',
  TipeOrderKanal.langsung: 'langsung',
};

@DataClassName('TipeOrderRow')
class TipeOrder extends Table {
  @override
  String get tableName => 'tipe_order';

  TextColumn get id => text()();
  TextColumn get tokoId => text()();
  TextColumn get nama => text()();
  TextColumn get kanal => textEnum<TipeOrderKanal>()();
  BoolColumn get pakaiMeja => boolean().withDefault(const Constant(false))();
  // numeric(5,2) di Postgres - persen markup, bukan uang, jadi REAL bukan
  // INTEGER rupiah (beda dari konvensi kolom uang di tabel lain).
  RealColumn get markupPersen => real().withDefault(const Constant(0))();
  IntColumn get urutan => integer().withDefault(const Constant(0))();
  BoolColumn get aktif => boolean().withDefault(const Constant(true))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
