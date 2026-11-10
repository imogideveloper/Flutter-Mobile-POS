import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/session_provider.dart';
import '../../../../core/providers/toko_profile_provider.dart';
import '../../../fitur/presentation/providers/feature_gate_provider.dart';
import '../../data/local/tables/transaksi_table.dart' show StatusPesanan;
import '../../domain/alur_status_pesanan.dart';
import '../../domain/pesanan_status.dart';
import 'transaksi_providers.dart';

/// Alur tahap status pesanan menurut jenis usaha toko (dokumen IMOGI 4.2).
/// Profil toko belum ada = alur standar.
final alurStatusPesananProvider = FutureProvider<AlurStatusPesanan>((ref) async {
  final profil = await ref.watch(tokoProfileProvider.future);
  return AlurStatusPesanan.untuk(profil?.jenisUsaha.kode);
});

/// Status awal untuk checkout baru, atau null bila fitur `status_pesanan`
/// belum terbuka di paket. Dioper ke `TransaksiRepository.checkout`.
Future<StatusPesanan?> statusPesananAwal(WidgetRef ref) async {
  final gate = await ref.read(featureGateProvider.future);
  if (!gate.has('status_pesanan')) return null;
  return (await ref.read(alurStatusPesananProvider.future)).awal;
}

/// Pesanan bernomor status di outlet ini sejak awal hari. Muat ulang
/// (invalidate) setelah mengubah status.
final pesananHariIniProvider = FutureProvider<List<PesananStatus>>((ref) {
  final outletId = ref.watch(currentOutletIdProvider);
  return ref.watch(transaksiRepositoryProvider).pesananHariIni(outletId);
});

/// Alur untuk pesanan bertipe antar (memuat tahap Diantar atau Dikirim).
final alurAntarStatusPesananProvider = FutureProvider<AlurStatusPesanan>((ref) async {
  final profil = await ref.watch(tokoProfileProvider.future);
  return AlurStatusPesanan.untuk(profil?.jenisUsaha.kode, termasukDiantar: true);
});
