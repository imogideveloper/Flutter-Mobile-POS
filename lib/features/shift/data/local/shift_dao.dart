import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/utils/id_generator.dart';
import 'tables/kas_shift_table.dart';
import 'tables/shift_table.dart';

part 'shift_dao.g.dart';

@DriftAccessor(tables: [Shift, KasShift])
class ShiftDao extends DatabaseAccessor<AppDatabase> with _$ShiftDaoMixin {
  ShiftDao(super.db);

  /// Shift yang perlu dikirim ke server: yang dirujuk transaksi belum-sync, yang masih
  /// buka, dan yang berubah sejak [sejakMs]. Server idempoten, jadi kirim ulang aman.
  Future<List<ShiftRow>> shiftUntukSync({required Set<String> idDirujuk, required int sejakMs}) =>
      (select(shift)
            ..where((t) =>
                t.deletedAt.isNull() &
                (t.id.isIn(idDirujuk) | t.status.equalsValue(ShiftStatus.buka) | t.updatedAt.isBiggerOrEqualValue(sejakMs)))
            ..orderBy([(t) => OrderingTerm.asc(t.dibukaPada)]))
          .get();

  Future<ShiftRow?> shiftTerbukaDiOutlet(String outletId) =>
      (select(shift)
            ..where((t) =>
                t.outletId.equals(outletId) &
                t.status.equalsValue(ShiftStatus.buka) &
                t.deletedAt.isNull()))
          .getSingleOrNull();

  /// Memastikan tidak ada dua shift 'buka' sekaligus di outlet yang sama -
  /// SQLite tidak punya padanan partial unique index Postgres untuk kasus
  /// ini (WHERE status = 'buka'), jadi dicek manual sebelum insert.
  Future<ShiftRow> bukaShift({
    required String id,
    required String tokoId,
    required String outletId,
    String? perangkatId,
    required String penggunaId,
    required int modalAwal,
  }) async {
    return transaction(() async {
      final sudahAda = await shiftTerbukaDiOutlet(outletId);
      if (sudahAda != null) {
        throw StateError('Sudah ada shift yang terbuka di outlet ini');
      }

      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      await into(shift).insert(ShiftCompanion.insert(
        id: id,
        tokoId: tokoId,
        outletId: outletId,
        perangkatId: Value(perangkatId),
        penggunaId: penggunaId,
        dibukaPada: now,
        modalAwal: Value(modalAwal),
        status: ShiftStatus.buka,
        createdAt: now,
        updatedAt: now,
      ));

      return (await (select(shift)..where((t) => t.id.equals(id))).getSingle());
    });
  }

  Future<void> tutupShift({
    required String shiftId,
    required int kasSeharusnya,
    required int kasAktual,
  }) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await (update(shift)..where((t) => t.id.equals(shiftId))).write(ShiftCompanion(
      ditutupPada: Value(now),
      kasSeharusnya: Value(kasSeharusnya),
      kasAktual: Value(kasAktual),
      selisih: Value(kasAktual - kasSeharusnya),
      status: const Value(ShiftStatus.tutup),
      updatedAt: Value(now),
    ));
  }

  Future<void> catatKasMasukKeluar({
    required String shiftId,
    required KasShiftJenis jenis,
    required int jumlah,
    required String keterangan,
    String? dibuatOleh,
  }) {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    return into(kasShift).insert(KasShiftCompanion.insert(
      id: generateId(),
      shiftId: shiftId,
      jenis: jenis,
      jumlah: jumlah,
      keterangan: keterangan,
      dibuatOleh: Value(dibuatOleh),
      createdAt: now,
      updatedAt: now,
    ));
  }
}
