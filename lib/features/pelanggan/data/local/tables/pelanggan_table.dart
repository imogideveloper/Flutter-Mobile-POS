import 'package:drift/drift.dart';

import 'level_member_table.dart';

@DataClassName('PelangganRow')
class Pelanggan extends Table {
  @override
  String get tableName => 'pelanggan';

  TextColumn get id => text()();
  TextColumn get tokoId => text()();
  TextColumn get nama => text()();
  TextColumn get noHp => text().nullable()();
  TextColumn get email => text().nullable()();
  // date di Postgres - epoch ms UTC tengah malam.
  IntColumn get tanggalLahir => integer().nullable()();
  TextColumn get levelMemberId => text().nullable().references(LevelMember, #id)();
  IntColumn get poin => integer().withDefault(const Constant(0))();
  IntColumn get totalBelanja => integer().withDefault(const Constant(0))();
  // Opsional (tahap 3b-1) - NULL = tidak ada batas. Kalau diisi, kasbon
  // baru yang membuat total utang (sum sisaTagihan) pelanggan ini melebihi
  // batas ditolak (lihat TransaksiRepository.checkout).
  IntColumn get batasKasbon => integer().nullable()();
  TextColumn get catatan => text().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
        {tokoId, noHp},
      ];
}
