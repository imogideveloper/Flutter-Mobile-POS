import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../../core/network/auth_session_store.dart';
import '../../../../core/network/dio_backend_api.dart';
import '../../../../core/providers/session_provider.dart';
import '../../../transaksi/presentation/providers/transaksi_providers.dart';
import '../../data/laporan_repository.dart';
import '../../domain/laporan_server.dart';
import '../../domain/ringkasan_laporan.dart';

final laporanRepositoryProvider = Provider<LaporanRepository>((ref) {
  return LaporanRepository(ref.watch(transaksiDaoProvider));
});

final periodeLaporanProvider = StateProvider<PeriodeLaporan>((ref) => PeriodeLaporan.hariIni);

/// Diisi hanya saat periodeLaporanProvider == custom (F3.C) - (awal, akhir).
final rentangCustomLaporanProvider = StateProvider<(DateTime, DateTime)?>((ref) => null);

final ringkasanLaporanProvider = FutureProvider<RingkasanLaporan>((ref) async {
  // Hitung ulang setiap ada transaksi baru atau perubahan status (void, refund). Tanpa ini Laporan memakai
  // hasil lama selama tab terbuka dan baru berubah setelah periode diganti.
  ref.watch(riwayatTransaksiProvider);
  final outletId = ref.watch(currentOutletIdProvider);
  final periode = ref.watch(periodeLaporanProvider);
  final rentangCustom = ref.watch(rentangCustomLaporanProvider);
  final repo = ref.watch(laporanRepositoryProvider);
  final lokal = await repo.ringkasan(outletId, periode, rentangCustom: rentangCustom);

  // HP yang baru masuk ulang tidak punya transaksi lama; ambil rekap periode dari server. Gagal (offline, paket
  // tidak mengizinkan) = tetap tampilkan hasil lokal.
  final (awalMs, akhirMs) = repo.rentang(periode, rentangCustom: rentangCustom);
  if (!laporanPerluDataServer(awalMs: awalMs, palingAwalLokalMs: await repo.tanggalAwalLokal(outletId))) return lokal;
  try {
    final sesi = await ref.read(authSessionStoreProvider).muat();
    if (sesi == null) return lokal;
    final api = ref.read(backendApiProvider);
    String iso(int ms) => DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toIso8601String();
    Future<Map<String, dynamic>> penjualan(int dari, int sampai) async => (await api.getJson(
          accessToken: sesi.accessToken,
          path: '/laporan/penjualan',
          query: {'dari': iso(dari), 'sampai': iso(sampai), 'outlet_id': sesi.outletId},
        )) as Map<String, dynamic>;
    final utama = await penjualan(awalMs, akhirMs);
    if ((utama['jumlah_transaksi'] as num).toInt() == 0) return lokal;
    final terlaris = await api.getJson(
      accessToken: sesi.accessToken,
      path: '/laporan/produk-terlaris',
      query: {'dari': iso(awalMs), 'sampai': iso(akhirMs), 'outlet_id': sesi.outletId},
    ) as List;
    Map<String, dynamic>? sebelumnya;
    try {
      sebelumnya = await penjualan(awalMs - (akhirMs - awalMs), awalMs);
    } catch (_) {
      sebelumnya = null; // pembanding tren boleh hilang
    }
    return ringkasanDariServer(
      penjualan: utama,
      terlaris: terlaris,
      sebelumnya: sebelumnya,
      zona: DateTime.now().timeZoneOffset,
    );
  } catch (_) {
    return lokal;
  }
});
