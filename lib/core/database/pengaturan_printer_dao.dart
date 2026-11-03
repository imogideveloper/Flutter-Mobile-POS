import 'package:drift/drift.dart';

import 'app_database.dart';
import 'tables/pengaturan_printer_table.dart';

part 'pengaturan_printer_dao.g.dart';

const _idDefault = 'default';

@DriftAccessor(tables: [PengaturanPrinter])
class PengaturanPrinterDao extends DatabaseAccessor<AppDatabase> with _$PengaturanPrinterDaoMixin {
  PengaturanPrinterDao(super.db);

  Stream<PengaturanPrinterRow?> watch() =>
      (select(pengaturanPrinter)..where((t) => t.id.equals(_idDefault))).watchSingleOrNull();

  Future<PengaturanPrinterRow?> ambil() =>
      (select(pengaturanPrinter)..where((t) => t.id.equals(_idDefault))).getSingleOrNull();

  Future<void> simpan({
    String? macAddress,
    String? namaPrinter,
    required int lebarKertasMm,
    required bool cetakOtomatis,
  }) {
    return into(pengaturanPrinter).insertOnConflictUpdate(
      PengaturanPrinterCompanion.insert(
        id: const Value(_idDefault),
        macAddress: Value(macAddress),
        namaPrinter: Value(namaPrinter),
        lebarKertasMm: Value(lebarKertasMm),
        cetakOtomatis: Value(cetakOtomatis),
      ),
    );
  }
}
