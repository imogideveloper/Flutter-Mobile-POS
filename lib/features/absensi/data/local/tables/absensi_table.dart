import 'package:drift/drift.dart';

import '../../../../../core/database/tables/outlets_table.dart';
import '../../../../../core/database/tables/pengguna_table.dart';
import '../../../../../core/database/tables/perangkat_table.dart';

enum AbsensiStatus { hadir, terlambat, izin, sakit, alpa }

@DataClassName('AbsensiRow')
class Absensi extends Table {
  @override
  String get tableName => 'absensi';

  TextColumn get id => text()();
  TextColumn get tokoId => text()();
  TextColumn get outletId => text().references(Outlets, #id)();
  TextColumn get penggunaId => text().references(Pengguna, #id)();
  TextColumn get perangkatId => text().nullable().references(Perangkat, #id)();
  IntColumn get jamMasuk => integer()();
  IntColumn get jamKeluar => integer().nullable()();
  TextColumn get fotoMasukUrl => text().nullable()();
  TextColumn get fotoKeluarUrl => text().nullable()();
  RealColumn get latMasuk => real().nullable()();
  RealColumn get lngMasuk => real().nullable()();
  TextColumn get status => textEnum<AbsensiStatus>().withDefault(const Constant('hadir'))();
  TextColumn get catatan => text().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
