import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers/session_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../data/local/tables/pajak_table.dart' show PajakTipe;
import '../../domain/pajak.dart';
import '../providers/pajak_providers.dart';

class PajakListPage extends ConsumerWidget {
  const PajakListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokoId = ref.watch(currentTokoIdProvider);
    final pajakAktif = ref.watch(pajakAktifProvider(tokoId));

    return Scaffold(
      appBar: AppBar(title: const Text('Pajak & Service')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/pajak/tambah'),
        tooltip: 'Tambah pajak/service',
        child: const Icon(Icons.add),
      ),
      body: pajakAktif.when(
        data: (items) {
          if (items.isEmpty) {
            return const EmptyState(
              icon: Icons.percent_outlined,
              message: 'Belum ada pajak/service aktif',
            );
          }
          final terurut = [...items]..sort((a, b) => a.urutan.compareTo(b.urutan));
          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.xl),
            itemCount: terurut.length,
            separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, index) => _PajakRow(pajak: terurut[index]),
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
      onTap: () => context.push('/pajak/edit', extra: pajak),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(pajak.nama, style: AppTypography.bodyEmphasis),
                Text(
                  pajak.tipe == PajakTipe.pajak ? 'Pajak' : 'Service charge',
                  style: AppTypography.secondary,
                ),
              ],
            ),
          ),
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
