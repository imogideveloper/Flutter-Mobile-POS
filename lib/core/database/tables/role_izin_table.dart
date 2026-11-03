import 'package:drift/drift.dart';

import 'izin_table.dart';
import 'role_table.dart';

/// Tabel junction murni (sama seperti di PostgreSQL): tanpa id sendiri,
/// tanpa updated_at/deleted_at - baris dihapus langsung, bukan soft delete.
@DataClassName('RoleIzinRow')
class RoleIzin extends Table {
  @override
  String get tableName => 'role_izin';

  TextColumn get roleId => text().references(Role, #id)();
  TextColumn get izinId => text().references(Izin, #id)();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {roleId, izinId};
}
