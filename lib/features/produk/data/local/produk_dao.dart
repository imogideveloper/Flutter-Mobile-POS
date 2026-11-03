import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import 'tables/kategori_table.dart';
import 'tables/produk_table.dart';
import 'tables/produk_varian_table.dart';

part 'produk_dao.g.dart';

@DriftAccessor(tables: [Produk, ProdukVarian, Kategori])
class ProdukDao extends DatabaseAccessor<AppDatabase> with _$ProdukDaoMixin {
  ProdukDao(super.db);

  Stream<List<ProdukRow>> watchProdukAktif() =>
      (select(produk)..where((t) => t.aktif.equals(true) & t.deletedAt.isNull()))
          .watch();

  /// Termasuk produk nonaktif - dipakai filter chip "Nonaktif" di daftar
  /// produk (watchProdukAktif sengaja tidak dipakai di sana karena memang
  /// hanya mengembalikan yang aktif).
  Stream<List<ProdukRow>> watchProdukSemua() =>
      (select(produk)..where((t) => t.deletedAt.isNull())).watch();

  Future<ProdukRow?> produkById(String id) =>
      (select(produk)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<ProdukRow?> findByBarcode(String barcode) =>
      (select(produk)..where((t) => t.barcode.equals(barcode) & t.deletedAt.isNull()))
          .getSingleOrNull();

  Future<List<ProdukVarianRow>> varianUntukProduk(String produkId) =>
      (select(produkVarian)..where((t) => t.produkId.equals(produkId) & t.deletedAt.isNull()))
          .get();

  Future<void> upsertProduk(ProdukCompanion data) =>
      into(produk).insertOnConflictUpdate(data);

  /// Update sebagian (bukan insertOnConflictUpdate) - sengaja tidak
  /// menyentuh createdAt baris yang sudah ada.
  Future<void> updateProduk(String id, ProdukCompanion data) =>
      (update(produk)..where((t) => t.id.equals(id))).write(data);

  /// Hapus PERMANEN (bukan soft-delete via deletedAt) - khusus "produk
  /// hantu" (lihat catatan idBerubah di produk_form_page.dart::_simpan):
  /// baris lokal dari era sebelum online-direct yang ternyata tidak pernah
  /// ada di server, dibuang begitu "lahir ulang" sbg produk server baru
  /// dgn id berbeda, supaya tidak nyangkut jadi duplikat kedua.
  Future<void> hapusPermanen(String id) =>
      (delete(produk)..where((t) => t.id.equals(id))).go();

  /// Dipakai pull-sync (SyncRepository) DAN form kategori online-direct
  /// (lihat kategori_form_page.dart) - kategori ikut masuk accessor ini
  /// krn produk punya FK ke kategori.
  Future<void> upsertKategori(KategoriCompanion data) =>
      into(kategori).insertOnConflictUpdate(data);

  Stream<List<KategoriRow>> watchKategoriAktif(String tokoId) =>
      (select(kategori)
            ..where((t) => t.tokoId.equals(tokoId) & t.deletedAt.isNull())
            ..orderBy([(t) => OrderingTerm.asc(t.urutan)]))
          .watch();

  /// Cache lokal setelah DELETE (soft delete) sukses di backend - pola
  /// sama dgn PajakDao.nonaktifkanLokal, bedanya kategori tidak punya
  /// kolom `aktif` (cuma deletedAt, sesuai skema resmi).
  Future<void> hapusKategoriLokal(String id) => (update(kategori)..where((t) => t.id.equals(id)))
      .write(KategoriCompanion(deletedAt: Value(DateTime.now().millisecondsSinceEpoch)));
}
