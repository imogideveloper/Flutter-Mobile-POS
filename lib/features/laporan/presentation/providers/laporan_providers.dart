import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../../core/providers/session_provider.dart';
import '../../../transaksi/presentation/providers/transaksi_providers.dart';
import '../../data/laporan_repository.dart';
import '../../domain/ringkasan_laporan.dart';

final laporanRepositoryProvider = Provider<LaporanRepository>((ref) {
  return LaporanRepository(ref.watch(transaksiDaoProvider));
});

final periodeLaporanProvider = StateProvider<PeriodeLaporan>((ref) => PeriodeLaporan.hariIni);

/// Diisi hanya saat periodeLaporanProvider == custom (F3.C) - (awal, akhir).
final rentangCustomLaporanProvider = StateProvider<(DateTime, DateTime)?>((ref) => null);

final ringkasanLaporanProvider = FutureProvider<RingkasanLaporan>((ref) {
  // Hitung ulang setiap ada transaksi baru atau perubahan status (void, refund). Tanpa ini Laporan memakai
  // hasil lama selama tab terbuka dan baru berubah setelah periode diganti.
  ref.watch(riwayatTransaksiProvider);
  final outletId = ref.watch(currentOutletIdProvider);
  final periode = ref.watch(periodeLaporanProvider);
  final rentangCustom = ref.watch(rentangCustomLaporanProvider);
  return ref.watch(laporanRepositoryProvider).ringkasan(outletId, periode, rentangCustom: rentangCustom);
});
