import 'package:drift/drift.dart';

/// Pengaturan printer Bluetooth (tahap 4 bagian D.2) - LOKAL PER HP, TIDAK
/// disync (SyncRepository tidak pernah membaca/menulis tabel ini) krn
/// setiap HP bisa pasang printer fisik yang beda, tidak ada artinya
/// disamakan lintas-device. Satu baris saja (PK literal 'default') - satu
/// HP cukup satu printer aktif.
@DataClassName('PengaturanPrinterRow')
class PengaturanPrinter extends Table {
  @override
  String get tableName => 'pengaturan_printer_lokal';

  TextColumn get id => text().withDefault(const Constant('default'))();
  TextColumn get macAddress => text().nullable()();
  TextColumn get namaPrinter => text().nullable()();
  IntColumn get lebarKertasMm => integer().withDefault(const Constant(58))();
  BoolColumn get cetakOtomatis => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}
