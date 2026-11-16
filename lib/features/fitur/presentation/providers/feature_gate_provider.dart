import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/database_provider.dart';
import '../../../../core/providers/session_provider.dart';
import '../../data/local/fitur_dao.dart';

final fiturDaoProvider = Provider<FiturDao>((ref) {
  return ref.watch(appDatabaseProvider).fiturDao;
});

/// Cache lokal status gating paket, diisi SyncRepository tiap habis pull
/// (lihat FiturDao.simpanStatusFitur) - dipakai widget `FiturTerkunci` dan
/// kode manapun yang perlu tahu "apakah fitur X terbuka utk toko ini",
/// TANPA pernah dipercaya sbg satu-satunya penjaga (server tetap menolak
/// 403 lewat require_fitur - lihat catatan di FiturTerkunci).
class FeatureGate {
  const FeatureGate({
    required this.paket,
    required this.kodeAktif,
    required this.batas,
    this.kebutuhan = const {},
  });

  final String? paket;
  final Set<String> kodeAktif;
  final Map<String, int> batas;

  /// Klasifikasi fitur untuk jenis usaha toko (Batch B): kode -> inti | opsional | na.
  final Map<String, String> kebutuhan;

  /// false hanya bila fitur ini ditandai tidak relevan (na) untuk jenis usaha toko. Kode yang tidak
  /// ada di klasifikasi (cache kosong, fitur lama) dianggap relevan agar tidak ada kontrol yang hilang diam-diam.
  bool relevan(String kode) => kebutuhan[kode] != 'na';

  bool has(String kode) => kodeAktif.contains(kode);

  /// Batas (mis. hari utk laporan_dasar) utk fitur ini - null kalau fitur
  /// ini tidak punya batas (termasuk kalau belum terbuka sama sekali).
  int? batasUntuk(String kode) => batas[kode];
}

/// FutureProvider (bukan StreamProvider) SENGAJA - menyatukan 2 query
/// `.watch()` (kodeAktif+batas) lewat nested asyncMap di atas satu
/// NativeDatabase (koneksi tunggal, sinkron) terbukti deadlock saat tes
/// (stream kedua nunggu giliran eksekusi yang masih "dipegang" callback
/// stream pertama). Status gating cuma berubah sesudah sync eksplisit -
/// cukup di-invalidate manual (lihat SyncRepository/lainnya_page.dart)
/// drpd dipaksa reaktif-otomatis lewat watch berlapis yang rawan ini.
final featureGateProvider = FutureProvider<FeatureGate>((ref) async {
  final dao = ref.watch(fiturDaoProvider);
  final tokoId = ref.watch(currentTokoIdProvider);

  final kodeAktif = await dao.kodeFiturAktif(tokoId);
  final paket = await dao.paketSaatIni(tokoId);
  final batas = await dao.semuaBatas(tokoId);
  final kebutuhan = await dao.semuaKebutuhan(tokoId);
  return FeatureGate(paket: paket, kodeAktif: kodeAktif, batas: batas, kebutuhan: kebutuhan);
});
