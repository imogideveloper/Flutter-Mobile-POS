import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import 'tables/batas_fitur_table.dart';
import 'tables/fitur_aktif_table.dart';
import 'tables/status_fitur_toko_table.dart';

part 'fitur_dao.g.dart';

@DriftAccessor(tables: [StatusFiturToko, FiturAktif, BatasFitur])
class FiturDao extends DatabaseAccessor<AppDatabase> with _$FiturDaoMixin {
  FiturDao(super.db);

  /// Dipanggil SyncRepository tiap habis pull - mengganti TOTAL status
  /// fitur toko (paket + kode aktif + batas), bukan upsert sebagian,
  /// supaya fitur yang baru DITUTUP (toko turun paket) ikut hilang dari
  /// cache lokal, bukan nyangkut dari pull sebelumnya.
  Future<void> simpanStatusFitur({
    required String tokoId,
    required String? paket,
    required List<String> kodeFiturAktif,
    required Map<String, int> batasPerKode,
    required int updatedAt,
  }) {
    return transaction(() async {
      await into(statusFiturToko).insertOnConflictUpdate(
        StatusFiturTokoCompanion.insert(tokoId: tokoId, paket: Value(paket), updatedAt: updatedAt),
      );

      await (delete(fiturAktif)..where((t) => t.tokoId.equals(tokoId))).go();
      for (final kode in kodeFiturAktif) {
        await into(fiturAktif).insert(FiturAktifCompanion.insert(tokoId: tokoId, kode: kode));
      }

      await (delete(batasFitur)..where((t) => t.tokoId.equals(tokoId))).go();
      for (final entry in batasPerKode.entries) {
        await into(batasFitur).insert(
          BatasFiturCompanion.insert(tokoId: tokoId, kode: entry.key, batas: entry.value),
        );
      }
    });
  }

  Future<String?> paketSaatIni(String tokoId) async {
    final row = await (select(statusFiturToko)..where((t) => t.tokoId.equals(tokoId))).getSingleOrNull();
    return row?.paket;
  }

  Stream<Set<String>> watchKodeFiturAktif(String tokoId) {
    final query = select(fiturAktif)..where((t) => t.tokoId.equals(tokoId));
    return query.watch().map((rows) => rows.map((r) => r.kode).toSet());
  }

  Future<Set<String>> kodeFiturAktif(String tokoId) async {
    final rows = await (select(fiturAktif)..where((t) => t.tokoId.equals(tokoId))).get();
    return rows.map((r) => r.kode).toSet();
  }

  Future<int?> batas(String tokoId, String kode) async {
    final row = await (select(batasFitur)
          ..where((t) => t.tokoId.equals(tokoId) & t.kode.equals(kode)))
        .getSingleOrNull();
    return row?.batas;
  }

  Stream<Map<String, int>> watchBatasFitur(String tokoId) {
    final query = select(batasFitur)..where((t) => t.tokoId.equals(tokoId));
    return query.watch().map((rows) => {for (final r in rows) r.kode: r.batas});
  }

  Future<Map<String, int>> semuaBatas(String tokoId) async {
    final rows = await (select(batasFitur)..where((t) => t.tokoId.equals(tokoId))).get();
    return {for (final r in rows) r.kode: r.batas};
  }
}
