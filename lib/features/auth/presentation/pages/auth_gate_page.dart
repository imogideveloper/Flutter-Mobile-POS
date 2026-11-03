import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/auth_session_store.dart';
import '../../../../core/providers/device_pairing_provider.dart';
import '../../../../core/providers/seed_provider.dart';
import '../../../../core/providers/session_provider.dart';
import '../../../fitur/presentation/providers/feature_gate_provider.dart';
import 'login_page.dart';
import 'otp_login_page.dart';

/// Pintu masuk app:
/// - Device belum pernah di-pairing (OTP) -> OtpLoginPage (sekali saja per
///   instalasi, lihat devicePairedProvider).
/// - Device sudah paired tapi belum ada yang pilih pengguna -> LoginPage
///   (pilih pengguna + PIN, ini alur ganti-kasir harian).
/// - Sudah login -> lempar ke /kasir (tab pertama bottom nav).
class AuthGatePage extends ConsumerWidget {
  const AuthGatePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final penggunaId = ref.watch(currentPenggunaIdProvider);

    if (penggunaId == null) {
      // seedProvider HARUS beres duluan sebelum OtpLoginPage maupun
      // LoginPage ditampilkan - OtpLoginPage._verifikasiOtp() langsung
      // menyentuh baris Owner lokal (lihat PenggunaRepository.
      // terapkanIdentitasBackend) begitu device belum pernah pairing;
      // kalau seed belum jalan, baris itu belum ada sama sekali (bukan
      // cuma data lama yang nyangkut) dan lookup-nya gagal diam-diam.
      final seed = ref.watch(seedProvider);
      final devicePaired = ref.watch(devicePairedProvider);
      // authBootstrapProvider memuat id toko/outlet/perangkat ASLI hasil
      // pairing sebelumnya (lihat auth_session_store.dart) - ditunggu DI
      // SINI (bukan cuma "fire and forget") supaya LoginPage/halaman
      // sesudahnya tidak sempat kebaca id placeholder sesaat sebelum
      // bootstrap selesai.
      final bootstrap = ref.watch(authBootstrapProvider);
      if (seed.isLoading) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      return devicePaired.when(
        data: (paired) {
          if (!paired) return OtpLoginPage(onSelesai: () {});
          return bootstrap.when(
            data: (_) {
              // App baru dibuka (bootstrap sesi baru selesai) - cache
              // FeatureGate lokal bisa basi (mis. paket diubah dari device
              // lain lalu di-sync di sini), jangan percaya cache lama.
              WidgetsBinding.instance.addPostFrameCallback((_) => ref.invalidate(featureGateProvider));
              return const LoginPage();
            },
            loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
            error: (error, stackTrace) => const LoginPage(),
          );
        },
        loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
        // Gagal baca status pairing (mis. secure storage error) - jangan
        // sampai mengunci kasir dari login sama sekali, tampilkan LoginPage
        // seperti biasa.
        error: (error, stackTrace) => const LoginPage(),
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) context.go('/kasir');
    });
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
