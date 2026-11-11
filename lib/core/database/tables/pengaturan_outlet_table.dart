import 'package:drift/drift.dart';

import 'outlets_table.dart';

/// PK = outletId sendiri (1:1 dengan Outlets), bukan id terpisah - sama
/// seperti skema Postgres.
@DataClassName('PengaturanOutletRow')
class PengaturanOutlet extends Table {
  @override
  String get tableName => 'pengaturan_outlet';

  TextColumn get outletId => text().references(Outlets, #id)();
  TextColumn get headerStruk => text().nullable()();
  TextColumn get footerStruk => text().nullable()();
  BoolColumn get tampilLogo => boolean().withDefault(const Constant(true))();
  IntColumn get lebarKertasMm => integer().withDefault(const Constant(58))();
  IntColumn get pembulatan => integer().withDefault(const Constant(0))();
  BoolColumn get izinkanStokMinus => boolean().withDefault(const Constant(true))();
  BoolColumn get wajibBukaShift => boolean().withDefault(const Constant(true))();
  BoolColumn get strukRingkas => boolean().withDefault(const Constant(false))();
  BoolColumn get pakaiNomorAntrean => boolean().withDefault(const Constant(false))();
  // Pengaturan nomor antrian (IMOGI no. 34): awalan dan angka awal tiap hari.
  TextColumn get antreanAwalan => text().withDefault(const Constant('A'))();
  IntColumn get antreanMulai => integer().withDefault(const Constant(1))();
  // Estimasi selesai pesanan (IMOGI no. 26): lama pengerjaan bawaan (menit); 0 = tidak dipakai.
  IntColumn get estimasiMenit => integer().withDefault(const Constant(0))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {outletId};
}
