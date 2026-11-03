import 'package:drift/drift.dart';

import 'fitur_table.dart';

/// paketId sengaja tanpa FK - tabel Paket cuma ada di server (lihat
/// PROMPT_Senior_Mobile_Dev_POS bagian 4.1), baris ini cuma cache read-only
/// hasil pull.
@DataClassName('PaketFiturRow')
class PaketFitur extends Table {
  @override
  String get tableName => 'paket_fitur';

  TextColumn get paketId => text()();
  TextColumn get fiturId => text().references(Fitur, #id)();
  IntColumn get batas => integer().nullable()();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {paketId, fiturId};
}
