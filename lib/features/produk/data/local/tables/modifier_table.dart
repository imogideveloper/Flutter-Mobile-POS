import 'package:drift/drift.dart';

import 'grup_modifier_table.dart';

@DataClassName('ModifierRow')
class Modifier extends Table {
  @override
  String get tableName => 'modifier';

  TextColumn get id => text()();
  TextColumn get grupModifierId => text().references(GrupModifier, #id)();
  TextColumn get nama => text()();
  IntColumn get hargaTambahan => integer().withDefault(const Constant(0))();
  IntColumn get urutan => integer().withDefault(const Constant(0))();
  BoolColumn get aktif => boolean().withDefault(const Constant(true))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
