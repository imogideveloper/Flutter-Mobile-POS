import 'package:drift/drift.dart';

enum PromoTipe { persen, nominal }
enum PromoCakupan { transaksi, produk }

@DataClassName('PromoRow')
class Promo extends Table {
  @override
  String get tableName => 'promo';

  TextColumn get id => text()();
  TextColumn get tokoId => text()();
  TextColumn get nama => text()();
  TextColumn get kode => text().nullable()();
  TextColumn get tipe => textEnum<PromoTipe>()();
  // Dual makna sesuai `tipe`: persen (0-100) atau nominal rupiah - makanya
  // REAL, bukan ikut konvensi kolom uang integer di tabel lain.
  RealColumn get nilai => real()();
  TextColumn get cakupan =>
      textEnum<PromoCakupan>().withDefault(const Constant('transaksi'))();
  IntColumn get minBelanja => integer().withDefault(const Constant(0))();
  IntColumn get maksDiskon => integer().nullable()();
  IntColumn get berlakuMulai => integer().nullable()();
  IntColumn get berlakuSampai => integer().nullable()();
  BoolColumn get aktif => boolean().withDefault(const Constant(true))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
