import 'package:drift/drift.dart';

import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/features/produk/data/local/tables/produk_pajak_table.dart';
import 'package:apps_pos/features/produk/data/local/tables/produk_table.dart';
import 'package:apps_pos/features/promo/data/local/tables/pajak_table.dart';

part 'pajak_dao.g.dart';

@DriftAccessor(tables: [Pajak, ProdukPajak, Produk])
class PajakDao extends DatabaseAccessor<AppDatabase> with _$PajakDaoMixin {
  PajakDao(super.db);

  Stream<List<PajakRow>> watchPajakAktif(String tokoId) =>
      (select(pajak)..where(
            (t) =>
                t.tokoId.equals(tokoId) &
                t.aktif.equals(true) &
                t.deletedAt.isNull(),
          ))
          .watch();

  Future<void> upsertPajak(PajakCompanion data) =>
      into(pajak).insertOnConflictUpdate(data);

  /// Tahap 5 C.6 - cache lokal setelah DELETE (soft delete) sukses di
  /// backend, supaya baris langsung hilang dari watchPajakAktif tanpa
  /// menunggu sync pull berikutnya.
  Future<void> nonaktifkanLokal(String id) =>
      (update(pajak)..where((t) => t.id.equals(id))).write(const PajakCompanion(aktif: Value(false)));

  Future<void> upsertProdukPajak(ProdukPajakCompanion data) =>
      into(produkPajak).insertOnConflictUpdate(data);

  /// Dipakai fitur `pajak_per_produk` - override pajak per produk
  /// (lih. HargaKeranjangProvider). Map kosong (bukan absen) utk produk
  /// tanpa override dianggap "pakai pajakDefault toko" (lihat
  /// ItemInput.pajakProduk di kalkulator.dart - null = default, list
  /// (termasuk kosong) = override).
  Future<Map<String, List<PajakRow>>> pajakUntukProduk(
    List<String> produkIds,
  ) async {
    if (produkIds.isEmpty) return {};
    final rows = await (select(produkPajak).join([
      innerJoin(pajak, pajak.id.equalsExp(produkPajak.pajakId)),
    ])..where(produkPajak.produkId.isIn(produkIds))).get();
    final hasil = <String, List<PajakRow>>{};
    for (final row in rows) {
      final produkId = row.readTable(produkPajak).produkId;
      hasil.putIfAbsent(produkId, () => []).add(row.readTable(pajak));
    }
    return hasil;
  }
}
