import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers/session_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../domain/kategori.dart';
import '../providers/kategori_providers.dart';

/// Kelola kategori produk (mis. Minuman/Makanan/Snack) - dipakai
/// mengelompokkan menu di Kasir/Produk. Online-direct (pola sama dgn
/// Pajak/Promo), BUKAN fitur berbayar.
class KategoriListPage extends ConsumerWidget {
  const KategoriListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokoId = ref.watch(currentTokoIdProvider);
    final kategoriAktif = ref.watch(kategoriAktifProvider(tokoId));

    return Scaffold(
      appBar: AppBar(title: const Text('Kategori produk')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/kategori/tambah'),
        tooltip: 'Tambah kategori',
        child: const Icon(Icons.add),
      ),
      body: kategoriAktif.when(
        data: (items) {
          if (items.isEmpty) {
            return const EmptyState(
              icon: Icons.category_outlined,
              message: 'Belum ada kategori.\nTambah kategori mis. Minuman, Makanan, Snack.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.xl),
            itemCount: items.length,
            separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, index) => _KategoriRow(kategori: items[index]),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(child: Text('Gagal memuat kategori: $error')),
      ),
    );
  }
}

class _KategoriRow extends StatelessWidget {
  const _KategoriRow({required this.kategori});

  final Kategori kategori;

  Color _warna() {
    if (kategori.warna == null) return Colors.grey;
    try {
      return Color(int.parse(kategori.warna!.replaceFirst('#', '0xFF')));
    } catch (_) {
      return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: () => context.push('/kategori/edit', extra: kategori),
      child: Row(
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(color: _warna(), shape: BoxShape.circle),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Text(kategori.nama, style: AppTypography.bodyEmphasis)),
          const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
        ],
      ),
    );
  }
}
