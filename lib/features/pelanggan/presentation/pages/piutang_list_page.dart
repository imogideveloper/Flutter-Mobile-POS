import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/avatar_initial.dart';
import '../../../../core/widgets/empty_state.dart';
import '../providers/piutang_providers.dart';

final _formatRupiah = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp', decimalDigits: 0);
final _formatTanggal = DateFormat('dd/MM/yyyy');

/// Daftar piutang (tahap 3b-1) - per pelanggan: total utang, jumlah
/// transaksi kasbon yang belum lunas, tanda lewat jatuh tempo. Tap satu
/// pelanggan -> PelunasanPage utk mencicil/melunasi.
class PiutangListPage extends ConsumerWidget {
  const PiutangListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final piutangAsync = ref.watch(piutangPelangganProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Piutang pelanggan')),
      body: piutangAsync.when(
        data: (daftar) {
          if (daftar.isEmpty) {
            return const EmptyState(
              icon: Icons.receipt_long_outlined,
              message: 'Tidak ada piutang kasbon saat ini.',
            );
          }
          final totalPiutang = daftar.fold<int>(0, (a, b) => a + b.totalUtang);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: AppCard(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Total piutang', style: AppTypography.bodyEmphasis),
                      Text(
                        _formatRupiah.format(totalPiutang),
                        style: AppTypography.headerTitle.copyWith(
                          fontSize: 20,
                          color: AppColors.primaryDark,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.xl),
                  itemCount: daftar.length,
                  separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, index) {
                    final p = daftar[index];
                    return AppCard(
                      onTap: () => context.push('/piutang/pelunasan', extra: p.pelangganId),
                      child: Row(
                        children: [
                          AvatarInitial.fromName(p.namaPelanggan),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(p.namaPelanggan, style: AppTypography.bodyEmphasis),
                                Text(
                                  '${p.jumlahTransaksi} transaksi'
                                  '${p.jatuhTempoTerdekat != null ? ' · jatuh tempo ${_formatTanggal.format(DateTime.fromMillisecondsSinceEpoch(p.jatuhTempoTerdekat!, isUtc: true))}' : ''}',
                                  style: AppTypography.secondary,
                                ),
                                if (p.lewatJatuhTempo)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppColors.dangerBg,
                                        borderRadius: BorderRadius.circular(999),
                                      ),
                                      child: Text(
                                        'Lewat jatuh tempo',
                                        style: AppTypography.secondary.copyWith(
                                          fontSize: 11,
                                          color: AppColors.dangerText,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Text(
                            _formatRupiah.format(p.totalUtang),
                            style: AppTypography.bodyEmphasis.copyWith(color: AppColors.primaryDark),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(child: Text('Gagal memuat piutang: $error')),
      ),
    );
  }
}
