import 'package:drift/drift.dart';

/// Cache hasil `/sync/pull` (field `paket`/`kode_fitur`/`batas_fitur`) -
/// SATU baris per toko (device single-tenant, tapi tetap diberi tokoId
/// supaya tidak nyangkut data basi kalau device pernah pairing ulang ke
/// toko lain). Tabel `Fitur`/`PaketFitur` yang sudah ada TIDAK dipakai
/// utk ini - keduanya memodelkan katalog LENGKAP + relasi paket_id/fitur_id
/// yang tidak sesuai bentuk respons `/sync/pull` (yang sudah disaring
/// server jadi "kode fitur mana saja yang aktif utk toko ini", bukan
/// katalog utuh) - lihat FiturDao.
@DataClassName('StatusFiturTokoRow')
class StatusFiturToko extends Table {
  @override
  String get tableName => 'status_fitur_toko';

  TextColumn get tokoId => text()();
  TextColumn get paket => text().nullable()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {tokoId};
}
