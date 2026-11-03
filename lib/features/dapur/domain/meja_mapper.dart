import '../../../core/database/app_database.dart';
import 'meja.dart' as domain;

extension MejaRowMapper on MejaRow {
  domain.Meja toDomain() => domain.Meja(
        id: id,
        outletId: outletId,
        nama: nama,
        area: area,
        kapasitas: kapasitas,
        urutan: urutan,
        aktif: aktif,
      );
}
