import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/network/sync_repository.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../domain/alur_status_pesanan.dart';
import '../../domain/pesanan_status.dart';
import '../providers/status_pesanan_providers.dart';
import '../providers/transaksi_providers.dart';

final _formatJam = DateFormat('HH:mm');

/// Halaman Status Pesanan (dokumen IMOGI no. 26): pesanan hari ini beserta
/// tahapnya. Pelayan/barista menekan tombol untuk memajukan satu tahap
/// (Baru, Diproses, Siap, Selesai; katering Dipesan, Dimasak, Siap kirim,
/// Dikirim, Selesai). Perubahan tersimpan lokal lebih dulu dan dikirim ke
/// server saat sync, jadi tetap jalan saat offline.
class StatusPesananPage extends ConsumerWidget {
  const StatusPesananPage({super.key});

  Future<void> _maju(WidgetRef ref, BuildContext context, PesananStatus p, TahapStatus tahap) async {
    await ref.read(transaksiRepositoryProvider).ubahStatusPesanan(p.id, tahap.kode);
    ref.invalidate(pesananHariIniProvider);
    // Best-effort: kalau offline/gagal, perubahan tetap terkirim pada sync berikutnya.
    unawaited(ref.read(syncRepositoryProvider).jalankan().then((_) {}, onError: (_) {}));
    if (context.mounted) {
      showAppToast(context, message: '${p.judul}: ${tahap.label}', variant: ToastVariant.success);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pesananAsync = ref.watch(pesananHariIniProvider);
    final alurStandar = ref.watch(alurStatusPesananProvider).value ?? AlurStatusPesanan.untuk(null);
    final alurAntar = ref.watch(alurAntarStatusPesananProvider).value ?? AlurStatusPesanan.untuk(null, termasukDiantar: true);
    AlurStatusPesanan alurUntuk(PesananStatus p) => p.antar ? alurAntar : alurStandar;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Status pesanan'),
        actions: [
          IconButton(
            key: const Key('statusPesanan.muatUlang'),
            tooltip: 'Muat ulang',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(pesananHariIniProvider),
          ),
        ],
      ),
      body: pesananAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Gagal memuat pesanan: $e')),
        data: (semua) {
          if (semua.isEmpty) {
            return const EmptyState(
              icon: Icons.receipt_long_outlined,
              message: 'Belum ada pesanan hari ini',
            );
          }
          final aktif = [for (final p in semua) if (!alurUntuk(p).sudahSelesai(p.status)) p];
          final tuntas = [for (final p in semua) if (alurUntuk(p).sudahSelesai(p.status)) p];
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            children: [
              Text('Perlu ditangani (${aktif.length})', style: AppTypography.cardTitle),
              const SizedBox(height: AppSpacing.sm),
              if (aktif.isEmpty)
                Text('Semua pesanan sudah selesai', style: AppTypography.secondary)
              else
                for (final p in aktif) _kartu(context, ref, p, alurUntuk(p)),
              if (tuntas.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xl),
                Text('Selesai hari ini (${tuntas.length})', style: AppTypography.cardTitle),
                const SizedBox(height: AppSpacing.sm),
                for (final p in tuntas) _kartu(context, ref, p, alurUntuk(p)),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _kartu(BuildContext context, WidgetRef ref, PesananStatus p, AlurStatusPesanan alur) {
    final berikut = alur.berikutnya(p.status);
    final waktu = _formatJam.format(DateTime.fromMillisecondsSinceEpoch(p.tanggal, isUtc: true).toLocal());
    final tuntas = alur.sudahSelesai(p.status);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        key: Key('statusPesanan.kartu.${p.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(p.judul, style: AppTypography.headerTitle.copyWith(fontSize: 20))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: tuntas ? AppColors.surface : AppColors.primaryTint,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: tuntas ? AppColors.borderDefault : AppColors.primaryTintBorder),
                  ),
                  child: Text(
                    alur.label(p.status),
                    key: Key('statusPesanan.status.${p.id}'),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: tuntas ? AppColors.textTertiary : AppColors.primaryDark,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text('$waktu · ${p.nomorStruk}', style: AppTypography.secondary),
            const SizedBox(height: AppSpacing.xs),
            Text(p.ringkasanItem),
            if (berikut != null) ...[
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: Key('statusPesanan.maju.${p.id}'),
                  onPressed: () => _maju(ref, context, p, berikut),
                  child: Text(berikut.labelAksi ?? berikut.label),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
