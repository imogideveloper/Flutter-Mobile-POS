import 'package:drift/drift.dart';

@DataClassName('GrupModifierRow')
class GrupModifier extends Table {
  @override
  String get tableName => 'grup_modifier';

  TextColumn get id => text()();
  TextColumn get tokoId => text()();
  TextColumn get nama => text()();
  IntColumn get minPilih => integer().withDefault(const Constant(0))();
  IntColumn get maksPilih => integer().withDefault(const Constant(1))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
