import 'package:drift/drift.dart';

enum SurveiTampilDi { struk, layarPelanggan, whatsapp }

const surveiTampilDiPostgresValue = <SurveiTampilDi, String>{
  SurveiTampilDi.struk: 'struk',
  SurveiTampilDi.layarPelanggan: 'layar_pelanggan',
  SurveiTampilDi.whatsapp: 'whatsapp',
};

@DataClassName('SurveiRow')
class Survei extends Table {
  @override
  String get tableName => 'survei';

  TextColumn get id => text()();
  TextColumn get tokoId => text()();
  TextColumn get judul => text()();
  TextColumn get tampilDi => textEnum<SurveiTampilDi>().withDefault(const Constant('struk'))();
  BoolColumn get aktif => boolean().withDefault(const Constant(true))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
