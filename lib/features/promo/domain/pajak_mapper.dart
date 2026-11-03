import '../../../core/database/app_database.dart';
import 'pajak.dart';

extension PajakRowMapper on PajakRow {
  Pajak toDomain() => Pajak(
        id: id,
        tokoId: tokoId,
        nama: nama,
        tipe: tipe,
        persen: persen,
        termasukHarga: termasukHarga,
        urutan: urutan,
        aktif: aktif,
      );
}
