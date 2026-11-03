import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import 'tables/meja_table.dart';

part 'meja_dao.g.dart';

/// Tahap 5 C.7 - DAO ini sebelumnya tidak ada sama sekali (tabel `meja`
/// cuma skema, belum ada akses) - meja SELALU online (Prinsip 1), DAO ini
/// cuma cache lokal setelah backend sukses, dibaca utk picker meja di
/// Keranjang.
@DriftAccessor(tables: [Meja])
class MejaDao extends DatabaseAccessor<AppDatabase> with _$MejaDaoMixin {
  MejaDao(super.db);

  Stream<List<MejaRow>> watchMejaAktif(String outletId) => (select(meja)
        ..where((t) => t.outletId.equals(outletId) & t.aktif.equals(true) & t.deletedAt.isNull())
        ..orderBy([(t) => OrderingTerm.asc(t.urutan)]))
      .watch();

  Future<void> upsertMeja(MejaCompanion data) => into(meja).insertOnConflictUpdate(data);

  Future<void> nonaktifkanLokal(String id) =>
      (update(meja)..where((t) => t.id.equals(id))).write(const MejaCompanion(aktif: Value(false)));
}
