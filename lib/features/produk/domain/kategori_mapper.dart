import '../../../core/database/app_database.dart';
import 'kategori.dart';

extension KategoriRowMapper on KategoriRow {
  Kategori toDomain() => Kategori(
        id: id,
        tokoId: tokoId,
        nama: nama,
        warna: warna,
        urutan: urutan,
        masukTiketDapur: masukTiketDapur,
      );
}
