import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/tables/pengaturan_outlet_table.dart';
import 'tables/harga_grosir_table.dart';
import 'tables/harga_outlet_table.dart';

part 'harga_dao.g.dart';

/// Data pendukung mesin hitung harga (lib/core/harga/kalkulator.dart) yang
/// dibaca lokal di keranjang: harga_outlet (override per outlet),
/// harga_grosir (tier), dan pengaturan_outlet (pembulatan) - semuanya
/// datang dari /sync/pull (lihat sync_repository.dart), bukan diubah
/// manual di HP (server yang menang, sama seperti produk/pajak/dkk).
@DriftAccessor(tables: [HargaOutlet, HargaGrosir, PengaturanOutlet])
class HargaDao extends DatabaseAccessor<AppDatabase> with _$HargaDaoMixin {
  HargaDao(super.db);

  Future<void> upsertHargaOutlet(HargaOutletCompanion data) =>
      into(hargaOutlet).insertOnConflictUpdate(data);

  Future<void> upsertHargaGrosir(HargaGrosirCompanion data) =>
      into(hargaGrosir).insertOnConflictUpdate(data);

  Future<void> upsertPengaturanOutlet(PengaturanOutletCompanion data) =>
      into(pengaturanOutlet).insertOnConflictUpdate(data);

  /// Satu-shot (bukan `.watch()`) - dibaca bersama beberapa query lain di
  /// hasilHargaKeranjangProvider; lihat catatan deadlock nested-watch di
  /// feature_gate_provider.dart, pola yang sama dihindari di sini.
  Future<List<HargaOutletRow>> hargaOutletUntukOutlet(String outletId) =>
      (select(hargaOutlet)
            ..where((t) => t.outletId.equals(outletId) & t.deletedAt.isNull()))
          .get();

  Future<List<HargaGrosirRow>> hargaGrosirUntukProduk(List<String> produkIds) {
    if (produkIds.isEmpty) return Future.value(const []);
    return (select(
      hargaGrosir,
    )..where((t) => t.produkId.isIn(produkIds) & t.deletedAt.isNull())).get();
  }

  Future<PengaturanOutletRow?> ambilPengaturanOutlet(String outletId) =>
      (select(
        pengaturanOutlet,
      )..where((t) => t.outletId.equals(outletId))).getSingleOrNull();

  /// Tahap 5 C.8 - cache lokal setelah DELETE (soft delete - backend set
  /// `deleted_at`, lihat router produk_lanjutan.py) sukses di backend.
  Future<void> hapusHargaGrosirLokal(String id) =>
      (update(hargaGrosir)..where((t) => t.id.equals(id)))
          .write(HargaGrosirCompanion(deletedAt: Value(DateTime.now().millisecondsSinceEpoch)));

  Future<void> hapusHargaOutletLokal(String id) =>
      (update(hargaOutlet)..where((t) => t.id.equals(id)))
          .write(HargaOutletCompanion(deletedAt: Value(DateTime.now().millisecondsSinceEpoch)));

  Future<List<HargaGrosirRow>> hargaGrosirUntukSatuProduk(String produkId) =>
      (select(hargaGrosir)..where((t) => t.produkId.equals(produkId) & t.deletedAt.isNull())).get();

  Future<List<HargaOutletRow>> hargaOutletUntukSatuProduk(String produkId) =>
      (select(hargaOutlet)..where((t) => t.produkId.equals(produkId) & t.deletedAt.isNull())).get();
}
