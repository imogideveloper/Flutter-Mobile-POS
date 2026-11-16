import 'package:drift/drift.dart';

/// Klasifikasi fitur untuk jenis usaha toko (Batch B) - hasil `/sync/pull.kebutuhan_fitur`:
/// `inti` | `opsional` | `na` (tidak relevan). Diganti TOTAL tiap pull, seperti [BatasFitur].
@DataClassName('KebutuhanFiturRow')
class KebutuhanFitur extends Table {
  @override
  String get tableName => 'kebutuhan_fitur';

  TextColumn get tokoId => text()();
  TextColumn get kode => text()();
  TextColumn get kebutuhan => text()();

  @override
  Set<Column> get primaryKey => {tokoId, kode};
}
