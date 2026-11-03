import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import 'tables/promo_produk_table.dart';
import 'tables/promo_table.dart';

part 'promo_dao.g.dart';

@DriftAccessor(tables: [Promo, PromoProduk])
class PromoDao extends DatabaseAccessor<AppDatabase> with _$PromoDaoMixin {
  PromoDao(super.db);

  Stream<List<PromoRow>> watchPromoAktif(String tokoId) => (select(promo)
        ..where((t) => t.tokoId.equals(tokoId) & t.aktif.equals(true) & t.deletedAt.isNull()))
      .watch();

  Future<void> upsertPromo(PromoCompanion data) => into(promo).insertOnConflictUpdate(data);

  Future<List<String>> produkIdUntukPromo(String promoId) => (select(promoProduk)
        ..where((t) => t.promoId.equals(promoId)))
      .map((row) => row.produkId)
      .get();

  /// Tahap 5 C.5 - cache lokal setelah DELETE (soft delete) sukses di
  /// backend, sama pola dgn PajakDao.nonaktifkanLokal.
  Future<void> nonaktifkanLokal(String id) =>
      (update(promo)..where((t) => t.id.equals(id))).write(const PromoCompanion(aktif: Value(false)));

  /// Cache lokal replace-all produk_ids setelah PUT /promo/{id}/produk
  /// sukses - dipakai kalkulasi_promo.dart (checkout) tanpa perlu nunggu
  /// sync penuh.
  Future<void> aturProdukLokal(String promoId, List<String> produkIds) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return transaction(() async {
      await (delete(promoProduk)..where((t) => t.promoId.equals(promoId))).go();
      for (final produkId in produkIds) {
        await into(promoProduk).insert(
          PromoProdukCompanion.insert(promoId: promoId, produkId: produkId, createdAt: now),
        );
      }
    });
  }
}
