import 'package:drift/drift.dart';

import '../../../../../core/database/tables/outlets_table.dart';

/// lebarKertasMm cuma boleh 58 atau 80 - divalidasi di domain layer, sama
/// seperti pola qty > 0 di ResepRow (lihat resep_table.dart), bukan lewat
/// CHECK constraint di skema.
@DataClassName('StasiunDapurRow')
class StasiunDapur extends Table {
  @override
  String get tableName => 'stasiun_dapur';

  TextColumn get id => text()();
  TextColumn get outletId => text().references(Outlets, #id)();
  TextColumn get nama => text()();
  TextColumn get printerAlamat => text().nullable()();
  IntColumn get lebarKertasMm => integer().withDefault(const Constant(58))();
  BoolColumn get aktif => boolean().withDefault(const Constant(true))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
