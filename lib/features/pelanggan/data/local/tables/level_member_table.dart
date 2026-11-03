import 'package:drift/drift.dart';

@DataClassName('LevelMemberRow')
class LevelMember extends Table {
  @override
  String get tableName => 'level_member';

  TextColumn get id => text()();
  TextColumn get tokoId => text()();
  TextColumn get nama => text()();
  IntColumn get minTotalBelanja => integer().withDefault(const Constant(0))();
  RealColumn get diskonPersen => real().withDefault(const Constant(0))();
  RealColumn get pengaliPoin => real().withDefault(const Constant(1))();
  IntColumn get urutan => integer().withDefault(const Constant(0))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
