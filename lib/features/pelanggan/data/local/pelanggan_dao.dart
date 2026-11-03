import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import 'tables/aturan_poin_table.dart';
import 'tables/level_member_table.dart';
import 'tables/pelanggan_table.dart';
import 'tables/riwayat_poin_table.dart';

part 'pelanggan_dao.g.dart';

@DriftAccessor(tables: [Pelanggan, LevelMember, RiwayatPoin, AturanPoin])
class PelangganDao extends DatabaseAccessor<AppDatabase> with _$PelangganDaoMixin {
  PelangganDao(super.db);

  Stream<List<PelangganRow>> watchPelangganAktif(String tokoId) => (select(pelanggan)
        ..where((t) => t.tokoId.equals(tokoId) & t.deletedAt.isNull())
        ..orderBy([(t) => OrderingTerm.asc(t.nama)]))
      .watch();

  Future<PelangganRow?> pelangganById(String id) =>
      (select(pelanggan)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<List<PelangganRow>> cariPelanggan(String tokoId, String kata) {
    final like = '%$kata%';
    return (select(pelanggan)
          ..where((t) =>
              t.tokoId.equals(tokoId) &
              t.deletedAt.isNull() &
              (t.nama.like(like) | t.noHp.like(like))))
        .get();
  }

  Future<void> upsertPelanggan(PelangganCompanion data) =>
      into(pelanggan).insertOnConflictUpdate(data);

  /// Tahap 5 C.3 - cache lokal setelah DELETE (soft delete) sukses di
  /// backend, sama pola dgn PajakDao.nonaktifkanLokal.
  Future<void> hapusLokal(String id) => (update(pelanggan)..where((t) => t.id.equals(id)))
      .write(PelangganCompanion(deletedAt: Value(DateTime.now().millisecondsSinceEpoch)));

  Stream<List<LevelMemberRow>> watchLevelMember(String tokoId) => (select(levelMember)
        ..where((t) => t.tokoId.equals(tokoId) & t.deletedAt.isNull())
        ..orderBy([(t) => OrderingTerm.asc(t.urutan)]))
      .watch();

  Future<void> upsertLevelMember(LevelMemberCompanion data) =>
      into(levelMember).insertOnConflictUpdate(data);

  /// Backend hard-delete level_member (tidak punya deleted_at - lihat
  /// router pelanggan.py) - cache lokal ikut hard delete, bukan soft.
  Future<void> hapusLevelMemberLokal(String id) =>
      (delete(levelMember)..where((t) => t.id.equals(id))).go();

  Stream<AturanPoinRow?> watchAturanPoin(String tokoId) =>
      (select(aturanPoin)..where((t) => t.tokoId.equals(tokoId))).watchSingleOrNull();

  Future<void> upsertAturanPoin(AturanPoinCompanion data) =>
      into(aturanPoin).insertOnConflictUpdate(data);

  /// Tambah/kurang poin pelanggan sekaligus catat riwayatnya. `delta` positif
  /// = dapat poin, negatif = ditukar.
  Future<void> catatPoin({
    required String pelangganId,
    String? transaksiId,
    required int delta,
    String? keterangan,
    required int now,
  }) {
    return transaction(() async {
      final row = await (select(pelanggan)..where((t) => t.id.equals(pelangganId))).getSingle();
      await (update(pelanggan)..where((t) => t.id.equals(pelangganId))).write(
        PelangganCompanion(poin: Value(row.poin + delta), updatedAt: Value(now)),
      );
      await into(riwayatPoin).insert(RiwayatPoinCompanion.insert(
        id: '$pelangganId-$now',
        pelangganId: pelangganId,
        transaksiId: Value(transaksiId),
        poin: delta,
        keterangan: Value(keterangan),
        createdAt: now,
        updatedAt: now,
      ));
    });
  }
}
