import '../../../core/utils/id_generator.dart';
import '../domain/shift.dart';
import '../domain/shift_mapper.dart';
import 'local/shift_dao.dart';
import 'local/tables/kas_shift_table.dart' show KasShiftJenis;

class ShiftRepository {
  ShiftRepository(this._dao);

  final ShiftDao _dao;

  Future<Shift?> shiftTerbukaDiOutlet(String outletId) async {
    final row = await _dao.shiftTerbukaDiOutlet(outletId);
    return row?.toDomain();
  }

  /// Melempar StateError (diteruskan dari ShiftDao.bukaShift) kalau ternyata
  /// sudah ada shift terbuka di outlet ini - UI wajib tangani.
  Future<Shift> bukaShift({
    required String tokoId,
    required String outletId,
    required String penggunaId,
    required int modalAwal,
  }) async {
    final row = await _dao.bukaShift(
      id: generateId(),
      tokoId: tokoId,
      outletId: outletId,
      penggunaId: penggunaId,
      modalAwal: modalAwal,
    );
    return row.toDomain();
  }

  Future<void> tutupShift({
    required String shiftId,
    required int kasSeharusnya,
    required int kasAktual,
  }) =>
      _dao.tutupShift(shiftId: shiftId, kasSeharusnya: kasSeharusnya, kasAktual: kasAktual);

  Future<void> catatKasMasukKeluar({
    required String shiftId,
    required KasShiftJenis jenis,
    required int jumlah,
    required String keterangan,
    String? dibuatOleh,
  }) =>
      _dao.catatKasMasukKeluar(
        shiftId: shiftId,
        jenis: jenis,
        jumlah: jumlah,
        keterangan: keterangan,
        dibuatOleh: dibuatOleh,
      );
}
