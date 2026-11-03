import 'package:drift/drift.dart';

@DataClassName('OutletRow')
class Outlets extends Table {
  @override
  String get tableName => 'outlet';

  TextColumn get id => text()();
  TextColumn get tokoId => text()();
  TextColumn get kode => text()();
  TextColumn get nama => text()();
  TextColumn get alamat => text().nullable()();
  TextColumn get noHp => text().nullable()();
  BoolColumn get aktif => boolean().withDefault(const Constant(true))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
        {tokoId, kode},
      ];
}
