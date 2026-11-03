import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import 'tables/metode_bayar_table.dart';

part 'metode_bayar_dao.g.dart';

@DriftAccessor(tables: [MetodeBayar])
class MetodeBayarDao extends DatabaseAccessor<AppDatabase> with _$MetodeBayarDaoMixin {
  MetodeBayarDao(super.db);

  Future<void> upsertMetodeBayar(MetodeBayarCompanion data) =>
      into(metodeBayar).insertOnConflictUpdate(data);

  /// Bersihkan baris "hantu" - metode bayar lokal yang dibuat
  /// `seedMetodeBayarDefault` SEBELUM device pairing (toko_id placeholder
  /// 'toko-default', ikut termigrasi ke toko_id asli oleh
  /// PairingDao.migrasikanTokoId) tapi id-nya TIDAK PERNAH sama dengan baris
  /// server (yang juga di-seed sendiri saat registrasi, lihat
  /// auth.py::_daftarkan_toko_baru) - upsertMetodeBayar di atas cuma
  /// menambah/update by id, TIDAK PERNAH menghapus baris lama itu, jadi
  /// toko yang sempat dipakai offline sebelum pairing berakhir py dobel.
  /// Metode bayar SELALU online-direct (dikelola lewat
  /// pengaturan_metode_bayar_page.dart) jadi aman anggap daftar dari server
  /// sbg satu-satunya sumber kebenaran per toko - baris lain dihapus.
  Future<void> hapusSelainIdServer({
    required String tokoId,
    required List<String> idDariServer,
  }) {
    if (idDariServer.isEmpty) return Future.value();
    return (delete(metodeBayar)
          ..where((t) => t.tokoId.equals(tokoId) & t.id.isNotIn(idDariServer)))
        .go();
  }

  Stream<List<MetodeBayarRow>> watchMetodeBayarAktif() =>
      (select(metodeBayar)
            ..where((t) => t.aktif.equals(true) & t.deletedAt.isNull())
            ..orderBy([(t) => OrderingTerm.asc(t.urutan)]))
          .watch();

  /// Termasuk yang nonaktif (beda dgn [watchMetodeBayarAktif]) - dipakai
  /// halaman pengaturan metode bayar (tahap 4) supaya kasir/owner bisa
  /// melihat & menyalakan kembali metode yang sudah dimatikan.
  Stream<List<MetodeBayarRow>> watchSemuaMetodeBayar() =>
      (select(metodeBayar)
            ..where((t) => t.deletedAt.isNull())
            ..orderBy([(t) => OrderingTerm.asc(t.urutan)]))
          .watch();
}
