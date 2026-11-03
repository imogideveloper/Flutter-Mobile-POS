import 'package:drift/drift.dart';

/// Satu baris per kode fitur yang AKTIF (terbuka) utk paket toko ini saat
/// ini - hasil `/sync/pull.kode_fitur`. Diganti TOTAL (hapus semua lalu
/// insert ulang) tiap pull, bukan di-upsert satu-satu, supaya fitur yang
/// baru DITUTUP (mis. toko turun paket) ikut hilang dari cache lokal.
@DataClassName('FiturAktifRow')
class FiturAktif extends Table {
  @override
  String get tableName => 'fitur_aktif';

  TextColumn get tokoId => text()();
  TextColumn get kode => text()();

  @override
  Set<Column> get primaryKey => {tokoId, kode};
}
