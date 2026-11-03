import '../../../core/database/app_database.dart';
import 'shift.dart';

extension ShiftRowMapper on ShiftRow {
  Shift toDomain() => Shift(
        id: id,
        tokoId: tokoId,
        outletId: outletId,
        perangkatId: perangkatId,
        penggunaId: penggunaId,
        dibukaPada: dibukaPada,
        ditutupPada: ditutupPada,
        modalAwal: modalAwal,
        kasSeharusnya: kasSeharusnya,
        kasAktual: kasAktual,
        selisih: selisih,
        catatan: catatan,
        status: status,
      );
}
