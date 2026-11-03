import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/id_generator.dart';
import 'local/tables/promo_table.dart' show PromoCakupan, PromoTipe;
import '../domain/promo.dart' as domain;
import '../domain/promo_mapper.dart';
import 'local/promo_dao.dart';

class PromoRepository {
  PromoRepository(this._dao);

  final PromoDao _dao;

  Stream<List<domain.Promo>> watchPromoAktif(String tokoId) =>
      _dao.watchPromoAktif(tokoId).map((rows) => rows.map((row) => row.toDomain()).toList());

  Future<List<String>> produkIdUntukPromo(String promoId) => _dao.produkIdUntukPromo(promoId);

  Future<void> tambahPromo({
    required String tokoId,
    required String nama,
    String? kode,
    required PromoTipe tipe,
    required double nilai,
    PromoCakupan cakupan = PromoCakupan.transaksi,
    int minBelanja = 0,
    int? maksDiskon,
  }) {
    final now = nowEpochMs();
    return _dao.upsertPromo(PromoCompanion.insert(
      id: generateId(),
      tokoId: tokoId,
      nama: nama,
      kode: Value(kode),
      tipe: tipe,
      nilai: nilai,
      cakupan: Value(cakupan),
      minBelanja: Value(minBelanja),
      maksDiskon: Value(maksDiskon),
      createdAt: now,
      updatedAt: now,
    ));
  }
}
