import '../data/local/tables/promo_table.dart' show PromoCakupan, PromoTipe;

class Promo {
  const Promo({
    required this.id,
    required this.tokoId,
    required this.nama,
    this.kode,
    required this.tipe,
    required this.nilai,
    required this.cakupan,
    required this.minBelanja,
    this.maksDiskon,
    required this.aktif,
  });

  final String id;
  final String tokoId;
  final String nama;
  final String? kode;
  final PromoTipe tipe;
  final double nilai;
  final PromoCakupan cakupan;
  final int minBelanja;
  final int? maksDiskon;
  final bool aktif;
}
