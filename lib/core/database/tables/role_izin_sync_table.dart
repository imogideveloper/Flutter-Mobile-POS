import 'package:drift/drift.dart';

import 'role_table.dart';

/// Tahap 5b (desain #2) - "role, daftar izin" dari /sync/pull. SENGAJA
/// tabel baru TERPISAH dari `role_izin`/`izin` lokal lama (yang diisi
/// `seedRoleDanOwner` utk role bawaan HASIL SEED, dipakai Owner sebelum
/// pernah pairing) - server kirim kode izin LANGSUNG (string), tanpa id
/// tabel master `izin` terpisah, jadi lebih sederhana punya tabel sendiri
/// drpd memetakan ulang ke skema id lokal lama. IzinService membaca DUA
/// sumber ini (sync dulu, fallback ke seed lama) - lihat izin_service.dart.
@DataClassName('RoleIzinSyncRow')
class RoleIzinSync extends Table {
  @override
  String get tableName => 'role_izin_sync';

  TextColumn get roleId => text().references(Role, #id)();
  TextColumn get izinKode => text()();

  @override
  Set<Column> get primaryKey => {roleId, izinKode};
}
