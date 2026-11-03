import 'local/produk_dao.dart';
import '../domain/kategori.dart' as domain;
import '../domain/kategori_mapper.dart';

class KategoriRepository {
  KategoriRepository(this._dao);

  final ProdukDao _dao;

  Stream<List<domain.Kategori>> watchKategoriAktif(String tokoId) =>
      _dao.watchKategoriAktif(tokoId).map((rows) => rows.map((row) => row.toDomain()).toList());
}
