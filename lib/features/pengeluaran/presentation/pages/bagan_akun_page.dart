import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/auth_session_store.dart';
import '../../../../core/network/backend_exception.dart';
import '../../../../core/network/dio_backend_api.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_card.dart';
import '../../domain/pengeluaran.dart' show labelKategoriPengeluaran;

/// Bagan akun standar (IMOGI no. 80, tahap 1; keputusan lead MoM 2026-11-25). Hanya baca: daftar akun tetap dari
/// server dan akun yang dipakai tiap kategori pengeluaran. Jurnal umum dan buku besar belum ada.
class AkunCoa {
  const AkunCoa({required this.kode, required this.nama, required this.kelompok});

  factory AkunCoa.fromJson(Map<String, dynamic> j) =>
      AkunCoa(kode: j['kode'] as String, nama: j['nama'] as String, kelompok: j['kelompok'] as String);

  final String kode;
  final String nama;
  final String kelompok;
}

class BaganAkun {
  const BaganAkun({required this.akun, required this.pemetaan});

  factory BaganAkun.fromJson(Map<String, dynamic> j) => BaganAkun(
        akun: [for (final a in j['akun'] as List) AkunCoa.fromJson(a as Map<String, dynamic>)],
        pemetaan: {
          for (final p in j['pemetaan_pengeluaran'] as List)
            (p as Map<String, dynamic>)['kategori'] as String: p['kode_akun'] as String,
        },
      );

  final List<AkunCoa> akun;

  /// Kategori pengeluaran ke kode akun.
  final Map<String, String> pemetaan;
}

const labelKelompokAkun = <String, String>{
  'aset': 'Aset',
  'kewajiban': 'Kewajiban',
  'ekuitas': 'Ekuitas',
  'pendapatan': 'Pendapatan',
  'hpp': 'Harga pokok penjualan',
  'beban': 'Beban usaha',
  'beban_lain': 'Beban lain-lain',
};

final baganAkunProvider = FutureProvider.autoDispose<BaganAkun>((ref) async {
  final sesi = await ref.read(authSessionStoreProvider).muat();
  if (sesi == null) throw const BackendException(message: 'Perangkat belum terhubung ke server');
  final json = await ref.read(backendApiProvider).getJson(accessToken: sesi.accessToken, path: '/akuntansi/coa');
  return BaganAkun.fromJson(json as Map<String, dynamic>);
});

class BaganAkunPage extends ConsumerWidget {
  const BaganAkunPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(baganAkunProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Bagan akun (CoA)')),
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  e is BackendException && e.tidakAdaKoneksi ? 'Butuh internet untuk memuat bagan akun.' : 'Gagal memuat: $e',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.md),
                OutlinedButton(onPressed: () => ref.invalidate(baganAkunProvider), child: const Text('Coba lagi')),
              ],
            ),
          ),
        ),
        data: (bagan) {
          final namaAkun = {for (final a in bagan.akun) a.kode: a.nama};
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            children: [
              Text(
                'Bagan akun standar untuk usaha makanan dan minuman. Beban seperti sewa dan listrik dicatat lewat '
                'Pengeluaran dan otomatis masuk ke akun di bawah. Daftar ini usulan awal dan belum bisa diubah; '
                'jurnal umum dan buku besar belum tersedia.',
                style: AppTypography.secondary,
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('Akun untuk kategori pengeluaran', style: AppTypography.bodyEmphasis),
              const SizedBox(height: AppSpacing.sm),
              AppCard(
                key: const Key('baganAkun.pemetaan'),
                child: Column(
                  children: [
                    for (final e in bagan.pemetaan.entries)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(labelKategoriPengeluaran(e.key)),
                        trailing: Text('${e.value} ${namaAkun[e.value] ?? ''}', style: AppTypography.secondary),
                      ),
                  ],
                ),
              ),
              for (final kelompok in labelKelompokAkun.keys)
                if (bagan.akun.any((a) => a.kelompok == kelompok)) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Text(labelKelompokAkun[kelompok]!, style: AppTypography.bodyEmphasis),
                  const SizedBox(height: AppSpacing.sm),
                  AppCard(
                    child: Column(
                      children: [
                        for (final a in bagan.akun.where((a) => a.kelompok == kelompok))
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Text(a.kode, style: AppTypography.secondary),
                            title: Text(a.nama),
                          ),
                      ],
                    ),
                  ),
                ],
            ],
          );
        },
      ),
    );
  }
}
