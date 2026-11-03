import 'package:drift/drift.dart';

import 'outlets_table.dart';
import 'pengguna_table.dart';

/// Tidak disebut eksplisit di daftar "disimpan di HP" (bagian 4.1 prompt),
/// tapi dibutuhkan secara logis - tanpa ini app tidak tahu outlet mana yang
/// boleh diakses pengguna yang sedang login. Junction murni sama seperti
/// role_izin.
@DataClassName('AksesOutletRow')
class AksesOutlet extends Table {
  @override
  String get tableName => 'akses_outlet';

  TextColumn get penggunaId => text().references(Pengguna, #id)();
  TextColumn get outletId => text().references(Outlets, #id)();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {penggunaId, outletId};
}
