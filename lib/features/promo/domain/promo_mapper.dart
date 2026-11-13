import '../../../core/database/app_database.dart';
import 'promo.dart' as domain;

extension PromoRowMapper on PromoRow {
  domain.Promo toDomain() => domain.Promo(
        id: id,
        tokoId: tokoId,
        nama: nama,
        kode: kode,
        tipe: tipe,
        nilai: nilai,
        cakupan: cakupan,
        minBelanja: minBelanja,
        maksDiskon: maksDiskon,
        aktif: aktif,
        khususUlangTahun: khususUlangTahun,
      );
}
