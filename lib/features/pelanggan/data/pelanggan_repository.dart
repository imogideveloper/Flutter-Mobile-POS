import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/id_generator.dart';
import '../domain/pelanggan.dart' as domain;
import '../domain/pelanggan_mapper.dart';
import 'local/pelanggan_dao.dart';

class PelangganRepository {
  PelangganRepository(this._dao);

  final PelangganDao _dao;

  Stream<List<domain.Pelanggan>> watchPelangganAktif(String tokoId) =>
      _dao.watchPelangganAktif(tokoId).map((rows) => rows.map((row) => row.toDomain()).toList());

  Future<List<domain.Pelanggan>> cariPelanggan(String tokoId, String kata) =>
      _dao.cariPelanggan(tokoId, kata).then((rows) => rows.map((row) => row.toDomain()).toList());

  Stream<List<domain.LevelMember>> watchLevelMember(String tokoId) =>
      _dao.watchLevelMember(tokoId).map((rows) => rows.map((row) => row.toDomain()).toList());

  Future<void> tambahPelanggan({
    required String tokoId,
    required String nama,
    String? noHp,
    String? email,
    String? catatan,
  }) {
    final now = nowEpochMs();
    return _dao.upsertPelanggan(PelangganCompanion.insert(
      id: generateId(),
      tokoId: tokoId,
      nama: nama,
      noHp: Value(noHp),
      email: Value(email),
      catatan: Value(catatan),
      createdAt: now,
      updatedAt: now,
    ));
  }

  Future<void> catatPoin({
    required String pelangganId,
    String? transaksiId,
    required int delta,
    String? keterangan,
  }) {
    return _dao.catatPoin(
      pelangganId: pelangganId,
      transaksiId: transaksiId,
      delta: delta,
      keterangan: keterangan,
      now: nowEpochMs(),
    );
  }
}
