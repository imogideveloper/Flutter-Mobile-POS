import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import 'tables/tipe_order_pajak_table.dart';
import 'tables/tipe_order_table.dart';

part 'tipe_order_dao.g.dart';

@DriftAccessor(tables: [TipeOrder, TipeOrderPajak])
class TipeOrderDao extends DatabaseAccessor<AppDatabase>
    with _$TipeOrderDaoMixin {
  TipeOrderDao(super.db);

  Stream<List<TipeOrderRow>> watchTipeOrderAktif(String tokoId) =>
      (select(tipeOrder)
            ..where(
              (t) =>
                  t.tokoId.equals(tokoId) &
                  t.aktif.equals(true) &
                  t.deletedAt.isNull(),
            )
            ..orderBy([(t) => OrderingTerm.asc(t.urutan)]))
          .watch();

  Future<void> upsertTipeOrder(TipeOrderCompanion data) =>
      into(tipeOrder).insertOnConflictUpdate(data);

  /// Tahap 5 C.7 - cache lokal setelah DELETE (soft delete) sukses di
  /// backend, sama pola dgn PajakDao.nonaktifkanLokal.
  Future<void> nonaktifkanLokal(String id) => (update(tipeOrder)..where((t) => t.id.equals(id)))
      .write(const TipeOrderCompanion(aktif: Value(false)));

  /// tipe_order_pajak tidak punya updated_at (relasi murni) - server
  /// selalu mengirim snapshot PENUH tiap pull (lihat sync.py), jadi di
  /// sini cukup insertOnConflictUpdate per baris, tidak perlu hapus baris
  /// lama yg sudah tidak ada di snapshot terbaru (gap kecil yg disengaja -
  /// link yg dihapus di server tidak akan ikut terhapus lokal sampai
  /// baris tipe_order_pajak lain membuatnya usang; dicatat di laporan).
  Future<void> upsertTipeOrderPajak(TipeOrderPajakCompanion data) =>
      into(tipeOrderPajak).insertOnConflictUpdate(data);

  Future<List<TipeOrderPajakRow>> semuaTipeOrderPajak() =>
      select(tipeOrderPajak).get();
}
