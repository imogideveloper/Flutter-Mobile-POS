import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/network/fitur_terkunci_event.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/fitur_terkunci_sheet.dart';
import 'features/fitur/presentation/providers/feature_gate_provider.dart';

/// Bug nyata (laporan pengguna: layar Laporan blank/abu-abu tepat sesudah
/// simpan rentang tanggal custom) - app ini banyak pakai `DateFormat(pola,
/// 'id_ID')` dgn nama bulan (mis. 'd MMM' -> "13 Okt"), tapi TIDAK PERNAH
/// memanggil initializeDateFormatting() sama sekali. `intl` melempar
/// LocaleDataException begitu format semacam itu dipakai sebelum data
/// locale-nya di-load - di release build, exception saat build widget
/// dirender sbg kotak abu-abu kosong (ErrorWidget default), persis yang
/// dilaporkan. Panggil SEKALI di sini, sebelum runApp, supaya SEMUA layar
/// yang pakai DateFormat('...', 'id_ID') (Laporan, Riwayat, dst) aman.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('id_ID');
  runApp(const ProviderScope(child: AppsPosApp()));
}

class AppsPosApp extends ConsumerWidget {
  const AppsPosApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Apps POS',
      theme: AppTheme.light,
      routerConfig: ref.watch(appRouterProvider),
      // Builder (bukan langsung di MaterialApp) supaya context di sini
      // sudah punya Navigator di atasnya - dibutuhkan showModalBottomSheet
      // dipanggil dari _FiturTerkunciListener di bawah.
      builder: (context, child) => _FiturTerkunciListener(child: child),
    );
  }
}

/// Dengarkan event global fitur_terkunci (lihat core/network/
/// fitur_terkunci_event.dart) - dipicu interceptor Dio begitu backend
/// menolak 403 `fitur_terkunci`, dari MANA PUN di app (tidak harus lewat
/// widget FiturTerkunci). Satu listener di root, bukan di tiap halaman.
class _FiturTerkunciListener extends ConsumerWidget {
  const _FiturTerkunciListener({required this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(fiturTerkunciEventProvider, (previous, next) {
      if (next == null) return;
      // Server menolak krn paket terkunci - cache FeatureGate lokal
      // berarti sudah basi (mis. paket baru berubah/kedaluwarsa tapi
      // belum sempat sync), jangan sampai dipakai lagi sebelum refresh.
      ref.invalidate(featureGateProvider);
      tampilkanFiturTerkunciSheet(context, fitur: next.fitur, paketMinimal: next.paketMinimal);
      ref.read(fiturTerkunciEventProvider.notifier).bersihkan();
    });
    return child ?? const SizedBox.shrink();
  }
}
