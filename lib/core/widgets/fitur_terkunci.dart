import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/fitur/presentation/providers/feature_gate_provider.dart';
import '../network/nama_fitur.dart';
import '../theme/app_colors.dart';
import 'fitur_terkunci_sheet.dart';

/// Bungkus tombol/menu yang hanya boleh dipakai kalau paket toko sudah
/// membuka `kode` fitur ini. Kalau belum terbuka: [child] ditampilkan
/// REDUP + ikon gembok kecil di pojok, dan ketukan APA PUN pada area ini
/// membuka bottom sheet "Tersedia di paket X" - TIDAK meneruskan ketukan
/// ke [child] (child tetap di-render, bukan disembunyikan, sesuai aturan
/// dokumen "fitur yang belum dibuka tetap tampil tapi terkunci, bukan
/// disembunyikan").
///
/// PENTING: ini murni kenyamanan UI (feedback instan tanpa round-trip ke
/// server) - gate SUNGGUHAN tetap di server (`require_fitur`/`has_fitur`,
/// lihat backend/app/services/fitur_service.py). Cache lokal ini bisa
/// basi (belum sync sejak upgrade/downgrade paket) - makanya interceptor
/// Dio (lihat dio_backend_api.dart) menampilkan sheet yang SAMA kalau
/// server menolak 403 `fitur_terkunci` walau cache lokal bilang terbuka.
class FiturTerkunci extends ConsumerWidget {
  const FiturTerkunci({super.key, required this.kode, required this.child});

  final String kode;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gateAsync = ref.watch(featureGateProvider);
    final gate = gateAsync is AsyncData<FeatureGate> ? gateAsync.value : null;
    // Belum ada cache sama sekali (belum pernah sync) - jangan kunci
    // duluan, biarkan server yang jadi penentu akhir saat dicoba.
    final terbuka = gate == null || gate.has(kode);

    if (terbuka) return child;

    return GestureDetector(
      key: Key('fiturTerkunci.$kode'),
      behavior: HitTestBehavior.opaque,
      onTap: () => tampilkanFiturTerkunciSheet(context, fitur: kode, paketMinimal: _paketMinimal(kode)),
      child: Stack(
        children: [
          Opacity(opacity: 0.45, child: IgnorePointer(child: child)),
          Positioned(
            right: 6,
            top: 6,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(color: AppColors.warningBg, shape: BoxShape.circle),
              child: const Icon(Icons.lock_outline, size: 14, color: AppColors.warningTextStrong),
            ),
          ),
        ],
      ),
    );
  }

  /// FeatureGate lokal tidak menyimpan "paket minimal" (cuma tahu
  /// terbuka/tidak utk paket SAAT INI) - tebakan kasar dari tingkat fitur
  /// resmi utk tampilan sheet lokal; kalau meleset, interceptor Dio di
  /// server tetap kirim nilai yang benar begitu sungguhan dicoba.
  String? _paketMinimal(String kode) => null;
}

/// Alias singkat utk dipakai di halaman - menampilkan nama fitur yang
/// manusiawi (dipanggil dari tempat yang butuh label, bukan dari widget
/// ini sendiri krn FiturTerkunci tidak merender teks nama).
String labelFitur(String kode) => namaTampilanFitur(kode);
