import '../domain/produk.dart';
import '../domain/produk_mapper.dart';
import 'local/produk_dao.dart';

/// Pola repository ini (dao -> domain entity lewat mapper) jadi acuan yang
/// diulang untuk modul stok/shift/transaksi.
///
/// Tahap 5b (desain #1, lanjutan) - CRUD tulis (tambah/ubah produk) sudah
/// dipindah jadi ONLINE-DIRECT di produk_form_page.dart (server dulu, baru
/// tulis-tembus ke ProdukDao) - repository ini sekarang HANYA baca cache
/// lokal (dipakai produk_list_page.dart, diisi oleh sync pull + tulis-
/// tembus form), tidak ada method tulis lagi di sini.
class ProdukRepository {
  ProdukRepository(this._dao);

  final ProdukDao _dao;

  Stream<List<Produk>> watchProdukAktif() =>
      _dao.watchProdukAktif().map((rows) => rows.map((row) => row.toDomain()).toList());

  Stream<List<Produk>> watchProdukSemua() =>
      _dao.watchProdukSemua().map((rows) => rows.map((row) => row.toDomain()).toList());
}
