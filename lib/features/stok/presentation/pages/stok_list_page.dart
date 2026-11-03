import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/providers/session_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/section_header.dart';
import '../../data/local/tables/mutasi_stok_table.dart' show MutasiJenis;
import '../../domain/mutasi_item.dart';
import '../../domain/stok_item.dart';
import '../providers/stok_providers.dart';

final _formatQty = NumberFormat.decimalPattern('id_ID');

const _labelJenisMutasi = {
  MutasiJenis.stokAwal: 'Stok awal',
  MutasiJenis.pembelian: 'Pembelian',
  MutasiJenis.penjualan: 'Penjualan',
  MutasiJenis.refund: 'Refund',
  MutasiJenis.voidTransaksi: 'Void',
  MutasiJenis.opname: 'Opname',
  MutasiJenis.transferMasuk: 'Transfer masuk',
  MutasiJenis.transferKeluar: 'Transfer keluar',
  MutasiJenis.penyesuaian: 'Penyesuaian',
  MutasiJenis.produksi: 'Produksi',
};

class StokListPage extends ConsumerWidget {
  const StokListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final outletId = ref.watch(currentOutletIdProvider);
    final stokOutlet = ref.watch(stokOutletProvider(outletId));
    final mutasiTerakhir = ref.watch(mutasiTerakhirProvider(outletId));

    return Scaffold(
      appBar: AppBar(title: const Text('Stok')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/stok/catat'),
        tooltip: 'Catat mutasi stok',
        child: const Icon(Icons.add),
      ),
      body: stokOutlet.when(
        data: (items) {
          if (items.isEmpty) {
            return const EmptyState(
              icon: Icons.inventory_2_outlined,
              message: 'Belum ada saldo stok di outlet ini',
            );
          }
          final menipis = items.where((i) => i.stokMenipis).toList();

          return ListView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            children: [
              if (menipis.isNotEmpty) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Perlu diisi ulang',
                      style: AppTypography.cardTitle.copyWith(fontSize: 15),
                    ),
                    Text('${menipis.length} produk', style: AppTypography.secondary),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (var i = 0; i < menipis.length; i++)
                        _StokMenipisRow(item: menipis[i], showDivider: i < menipis.length - 1),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
              ],
              const SectionHeader(label: 'Semua stok'),
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var i = 0; i < items.length; i++)
                      _StokRow(item: items[i], showDivider: i < items.length - 1),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text('Mutasi terakhir', style: AppTypography.cardTitle.copyWith(fontSize: 15)),
              const SizedBox(height: AppSpacing.sm),
              mutasiTerakhir.when(
                data: (moves) => moves.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                        child: Text('Belum ada mutasi', style: AppTypography.secondary),
                      )
                    : AppCard(
                        padding: EdgeInsets.zero,
                        child: Column(
                          children: [
                            for (var i = 0; i < moves.length; i++)
                              _MutasiRow(item: moves[i], showDivider: i < moves.length - 1),
                          ],
                        ),
                      ),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stackTrace) => Text('Gagal memuat mutasi: $error'),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(child: Text('Gagal memuat stok: $error')),
      ),
    );
  }
}

class _StokMenipisRow extends StatelessWidget {
  const _StokMenipisRow({required this.item, required this.showDivider});

  final StokItem item;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final pct = item.batasMinimum <= 0 ? 0.0 : (item.jumlah / (item.batasMinimum * 2)).clamp(0.05, 1.0);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      decoration: showDivider
          ? const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.borderDefault)))
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(item.produkNama, style: AppTypography.bodyEmphasis),
              Text(
                _formatQty.format(item.jumlah),
                style: AppTypography.bodyEmphasis.copyWith(color: AppColors.warningTextStrong),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 6,
              backgroundColor: AppColors.borderDefault,
              color: const Color(0xFFD97A1E),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Batas minimum ${_formatQty.format(item.batasMinimum)}',
            style: AppTypography.secondary,
          ),
        ],
      ),
    );
  }
}

class _StokRow extends StatelessWidget {
  const _StokRow({required this.item, required this.showDivider});

  final StokItem item;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      alignment: Alignment.centerLeft,
      decoration: showDivider
          ? const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.borderDefault)))
          : null,
      child: Row(
        children: [
          Expanded(child: Text(item.produkNama, style: AppTypography.bodyEmphasis)),
          if (item.stokMenipis)
            const Padding(
              padding: EdgeInsets.only(right: AppSpacing.xs),
              child: Icon(Icons.warning_amber_rounded, size: 16, color: AppColors.warningTextStrong),
            ),
          Text(
            _formatQty.format(item.jumlah),
            style: AppTypography.moneyAmount.copyWith(
              color: item.stokMenipis ? AppColors.warningTextStrong : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _MutasiRow extends StatelessWidget {
  const _MutasiRow({required this.item, required this.showDivider});

  final MutasiItem item;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final warna = item.masuk ? AppColors.primaryDark : AppColors.dangerText;
    final tanda = item.masuk ? '+' : '';
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
      decoration: showDivider
          ? const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.borderDefault)))
          : null,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.produkNama, style: AppTypography.bodyEmphasis),
                Text(_labelJenisMutasi[item.jenis] ?? item.jenis.name, style: AppTypography.secondary),
              ],
            ),
          ),
          Text(
            '$tanda${_formatQty.format(item.qty)}',
            style: AppTypography.bodyEmphasis.copyWith(color: warna),
          ),
        ],
      ),
    );
  }
}
