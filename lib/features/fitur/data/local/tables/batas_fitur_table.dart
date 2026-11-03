import 'package:drift/drift.dart';

/// Batas (mis. hari utk laporan_dasar) per kode fitur - hasil
/// `/sync/pull.batas_fitur`. Sama seperti FiturAktif, diganti TOTAL tiap
/// pull (bukan upsert) - kode yang tidak lagi punya batas (atau sudah
/// tidak aktif) ikut terhapus dari cache ini.
@DataClassName('BatasFiturRow')
class BatasFitur extends Table {
  @override
  String get tableName => 'batas_fitur';

  TextColumn get tokoId => text()();
  TextColumn get kode => text()();
  IntColumn get batas => integer()();

  @override
  Set<Column> get primaryKey => {tokoId, kode};
}
