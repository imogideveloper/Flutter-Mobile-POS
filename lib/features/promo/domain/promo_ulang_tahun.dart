import 'promo.dart';

/// Promo ulang tahun yang diterapkan otomatis saat pelanggan yang berulang tahun dipilih di keranjang
/// (IMOGI no. 56). FUNGSI MURNI. Hanya bila pelanggan berulang tahun hari ini DAN kasir belum memilih promo
/// apa pun (pilihan kasir tidak pernah ditimpa). Bila ada beberapa promo ulang tahun aktif, dipilih yang
/// pertama menurut urutan [promoAktif]. null = tidak ada yang diterapkan.
Promo? promoUlangTahunOtomatis({
  required List<Promo> promoAktif,
  required bool pelangganUlangTahun,
  required String? promoTerpilihId,
}) {
  if (!pelangganUlangTahun || promoTerpilihId != null) return null;
  for (final p in promoAktif) {
    if (p.aktif && p.khususUlangTahun) return p;
  }
  return null;
}
