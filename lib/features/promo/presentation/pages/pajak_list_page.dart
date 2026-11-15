import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/auth_session_store.dart';
import '../../../../core/network/dio_backend_api.dart';
import '../../../../core/providers/session_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../data/local/tables/pajak_table.dart' show PajakTipe;
import '../../domain/pajak.dart';
import '../../domain/status_pajak_usaha.dart';
import '../providers/pajak_providers.dart';

class PajakListPage extends ConsumerWidget {
  const PajakListPage({super.key});

  /// Nyalakan/matikan SEMUA pajak (bukan service charge) sekaligus - itulah arti
  /// "usaha kena pajak / tidak kena pajak". Ditulis ke server dulu (pajak selalu
  /// online, sama dengan form), baru cache lokal diperbarui.
  Future<void> _ubahStatusPajak(WidgetRef ref, BuildContext context, List<Pajak> semua, bool kena) async {
    final sesi = await ref.read(authSessionStoreProvider).muat();
    if (sesi == null) {
      if (context.mounted) {
        showAppToast(context, message: 'Perangkat belum terhubung ke server', variant: ToastVariant.warning);
      }
      return;
    }
    try {
      for (final p in semua.where((p) => p.tipe == PajakTipe.pajak && p.aktif != kena)) {
        await ref.read(backendApiProvider).patchJson(
              accessToken: sesi.accessToken,
              path: '/pajak/${p.id}',
              body: {'aktif': kena},
            );
        await ref.read(pajakDaoProvider).ubahAktifLokal(p.id, kena);
      }
    } catch (e) {
      if (context.mounted) {
        showAppToast(context, message: 'Gagal mengubah status pajak: $e', variant: ToastVariant.danger);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokoId = ref.watch(currentTokoIdProvider);
    final semuaAsync = ref.watch(pajakSemuaProvider(tokoId));

    return Scaffold(
      appBar: AppBar(title: const Text('Pajak & Service')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/pajak/tambah'),
        tooltip: 'Tambah pajak/service',
        child: const Icon(Icons.add),
      ),
      body: semuaAsync.when(
        data: (items) {
          if (items.isEmpty) {
            return const EmptyState(
              icon: Icons.percent_outlined,
              message: 'Belum ada pajak/service. Ketuk + untuk menambah (ada pilihan cepat PB1, PPN, dan Service).',
            );
          }
          final terurut = [...items]..sort((a, b) {
              if (a.aktif != b.aktif) return a.aktif ? -1 : 1;
              return a.urutan.compareTo(b.urutan);
            });
          final status = statusPajakUsaha(items);
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            children: [
              if (status != StatusPajakUsaha.belumDiatur)
                AppCard(
                  key: const Key('pajakList.statusUsaha'),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Usaha kena pajak', style: AppTypography.bodyEmphasis),
                            Text(
                              status == StatusPajakUsaha.kena
                                  ? 'Pajak diterapkan pada transaksi.'
                                  : 'Tidak kena pajak: pajak tidak dihitung (service charge tetap berlaku).',
                              style: AppTypography.secondary,
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        key: const Key('pajakList.saklarKenaPajak'),
                        value: status == StatusPajakUsaha.kena,
                        onChanged: (v) => _ubahStatusPajak(ref, context, items, v),
                      ),
                    ],
                  ),
                ),
              if (status != StatusPajakUsaha.belumDiatur) const SizedBox(height: AppSpacing.md),
              for (final p in terurut) ...[
                _PajakRow(pajak: p),
                const SizedBox(height: AppSpacing.sm),
              ],
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(child: Text('Gagal memuat pajak: $error')),
      ),
    );
  }
}

class _PajakRow extends StatelessWidget {
  const _PajakRow({required this.pajak});

  final Pajak pajak;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      key: Key('pajakList.baris.${pajak.id}'),
      onTap: () => context.push('/pajak/edit', extra: pajak),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pajak.nama,
                  style: AppTypography.bodyEmphasis.copyWith(color: pajak.aktif ? null : AppColors.textTertiary),
                ),
                Text(
                  pajak.tipe == PajakTipe.pajak ? 'Pajak' : 'Service charge',
                  style: AppTypography.secondary,
                ),
              ],
            ),
          ),
          if (!pajak.aktif) ...[
            const AppBadge(label: 'Nonaktif'),
            const SizedBox(width: AppSpacing.sm),
          ],
          if (pajak.termasukHarga) ...[
            const AppBadge(label: 'Termasuk harga', variant: BadgeVariant.info),
            const SizedBox(width: AppSpacing.sm),
          ],
          Text(
            '${pajak.persen.toStringAsFixed(pajak.persen.truncateToDouble() == pajak.persen ? 0 : 2)}%',
            style: AppTypography.moneyAmount.copyWith(color: AppColors.primaryDark, fontSize: 16),
          ),
        ],
      ),
    );
  }
}
