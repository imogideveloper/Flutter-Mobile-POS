import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/id_generator.dart';
import 'local/pajak_dao.dart';
import 'local/tables/pajak_table.dart' show PajakTipe;
import '../domain/pajak.dart' as domain;
import '../domain/pajak_mapper.dart';

class PajakRepository {
  PajakRepository(this._dao);

  final PajakDao _dao;

  Stream<List<domain.Pajak>> watchPajakAktif(String tokoId) =>
      _dao.watchPajakAktif(tokoId).map((rows) => rows.map((row) => row.toDomain()).toList());

  Future<void> tambahPajak({
    required String tokoId,
    required String nama,
    required PajakTipe tipe,
    required double persen,
    bool termasukHarga = false,
    int urutan = 0,
  }) {
    final now = nowEpochMs();
    return _dao.upsertPajak(PajakCompanion.insert(
      id: generateId(),
      tokoId: tokoId,
      nama: nama,
      tipe: Value(tipe),
      persen: persen,
      termasukHarga: Value(termasukHarga),
      urutan: Value(urutan),
      createdAt: now,
      updatedAt: now,
    ));
  }
}
