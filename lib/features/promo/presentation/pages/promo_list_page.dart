import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../data/local/tables/promo_table.dart' show PromoCakupan, PromoTipe;
import '../../domain/promo.dart';
import '../providers/promo_providers.dart';

/// Tahap 5 C.5 - "daftar, buat, edit, nonaktifkan; pilih produk dan
/// outlet". Sama gaya dgn PajakListPage.
class PromoListPage extends ConsumerWidget {
  const PromoListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final promoAktif = ref.watch(promoAktifProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Promo')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/promo/tambah'),
        tooltip: 'Tambah promo',
        child: const Icon(Icons.add),
      ),
      body: promoAktif.when(
        data: (items) {
          if (items.isEmpty) {
            return const EmptyState(
              icon: Icons.local_offer_outlined,
              message: 'Belum ada promo aktif.\nTambah promo pertama lewat tombol di bawah.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.xl),
            itemCount: items.length,
            separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, index) => _PromoRow(promo: items[index]),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(child: Text('Gagal memuat promo: $error')),
      ),
    );
  }
}

class _PromoRow extends StatelessWidget {
  const _PromoRow({required this.promo});

  final Promo promo;

  String get _nilaiLabel =>
      promo.tipe == PromoTipe.persen ? '${promo.nilai.toStringAsFixed(0)}%' : 'Rp${promo.nilai.toStringAsFixed(0)}';

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: () => context.push('/promo/edit', extra: promo),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(promo.nama, style: AppTypography.bodyEmphasis),
                Row(
                  children: [
                    if (promo.kode != null) ...[
                      Text(promo.kode!, style: AppTypography.secondary),
                      const SizedBox(width: AppSpacing.sm),
                    ],
                    Text(
                      promo.cakupan == PromoCakupan.produk ? 'Produk tertentu' : 'Seluruh transaksi',
                      style: AppTypography.secondary,
                    ),
                  ],
                ),
              ],
            ),
          ),
          Text(_nilaiLabel, style: AppTypography.moneyAmount.copyWith(color: AppColors.primaryDark, fontSize: 16)),
        ],
      ),
    );
  }
}
