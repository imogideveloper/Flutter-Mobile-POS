import 'package:drift/drift.dart';

/// tokoId NULL = role bawaan sistem (Owner/Manajer/Kasir), bukan role
/// custom milik satu toko - sama seperti kolom role.toko_id yang nullable
/// di skema Postgres. Ditaruh di core (bukan folder fitur) karena dipakai
/// langsung oleh Pengguna, sama seperti outlet/perangkat.
@DataClassName('RoleRow')
class Role extends Table {
  @override
  String get tableName => 'role';

  TextColumn get id => text()();
  TextColumn get tokoId => text().nullable()();
  TextColumn get nama => text()();
  BoolColumn get isSystem => boolean().withDefault(const Constant(false))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
