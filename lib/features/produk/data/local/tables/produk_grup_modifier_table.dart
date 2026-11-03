import 'package:drift/drift.dart';

import 'grup_modifier_table.dart';
import 'produk_table.dart';

/// Tabel junction murni (sama seperti di PostgreSQL): tanpa id sendiri,
/// tanpa updated_at/deleted_at - baris dihapus langsung, bukan soft delete.
@DataClassName('ProdukGrupModifierRow')
class ProdukGrupModifier extends Table {
  @override
  String get tableName => 'produk_grup_modifier';

  TextColumn get produkId => text().references(Produk, #id)();
  TextColumn get grupModifierId => text().references(GrupModifier, #id)();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {produkId, grupModifierId};
}
