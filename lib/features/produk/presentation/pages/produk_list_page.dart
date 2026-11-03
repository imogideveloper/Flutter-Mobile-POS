import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/providers/session_provider.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/avatar_initial.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../stok/domain/stok_item.dart';
import '../../../stok/presentation/providers/stok_providers.dart';
import '../../data/local/tables/produk_table.dart' show ProdukTipe;
import '../../domain/produk.dart';
import '../providers/produk_providers.dart';

final _formatRupiah = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp', decimalDigits: 0);

enum _FilterChip { semua, stokMenipis, nonaktif }

(Color bg, Color fg) _tintUntukTipe(ProdukTipe tipe) => switch (tipe) {
  ProdukTipe.barang => (AppColors.brownBg, AppColors.brownText),
  ProdukTipe.jasa => (AppColors.indigoBg, AppColors.indigoText),
  ProdukTipe.bahanBaku => (AppColors.borderDefault, AppColors.textSecondary),
  ProdukTipe.bundling => (AppColors.primaryTint, AppColors.primaryDark),
};

String _labelTipe(ProdukTipe tipe) => switch (tipe) {
  ProdukTipe.barang => 'Barang',
  ProdukTipe.jasa => 'Jasa',
  ProdukTipe.bahanBaku => 'Bahan baku · tidak dijual',
  ProdukTipe.bundling => 'Bundling',
};

class ProdukListPage extends ConsumerStatefulWidget {
  const ProdukListPage({super.key});

  @override
  ConsumerState<ProdukListPage> createState() => _ProdukListPageState();
}

class _ProdukListPageState extends ConsumerState<ProdukListPage> {
  _FilterChip _filter = _FilterChip.semua;
  String _kataCari = '';

  @override
  Widget build(BuildContext context) {
    final tokoId = ref.watch(currentTokoIdProvider);
    final outletId = ref.watch(currentOutletIdProvider);
    final penggunaId = ref.watch(currentPenggunaIdProvider);
    final penggunaAktif = ref.watch(penggunaAktifProvider(tokoId));
    final namaPengguna = penggunaAktif.maybeWhen(
      data: (items) => items.where((p) => p.id == penggunaId).firstOrNull?.nama,
      orElse: () => null,
    );
    final stokOutlet = ref.watch(stokOutletProvider(outletId));
    final produkAsync = _filter == _FilterChip.nonaktif
        ? ref.watch(produkSemuaProvider)
        : ref.watch(produkAktifProvider);

    final stokByProdukId = <String, StokItem>{
      for (final item in stokOutlet.maybeWhen(data: (v) => v, orElse: () => const <StokItem>[]))
        item.produkId: item,
    };
    final jumlahMenipis = stokByProdukId.values.where((s) => s.stokMenipis).length;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Produk'),
            if (namaPengguna != null)
              Text(namaPengguna, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => context.push('/stok'),
            child: const Text('Kelola stok'),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'logout') {
                ref.read(currentPenggunaIdProvider.notifier).logout();
                context.go('/');
                return;
              }
              context.push(value);
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: '/shift', child: Text('Shift')),
              PopupMenuItem(value: '/pajak', child: Text('Pajak & Service')),
              PopupMenuItem(value: '/pengguna', child: Text('Kelola Pengguna')),
              PopupMenuDivider(),
              PopupMenuItem(value: 'logout', child: Text('Keluar')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: AppColors.surface,
            padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.md),
            child: Column(
              children: [
                TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search, size: 20),
                    hintText: 'Cari produk',
                    isDense: true,
                  ),
                  onChanged: (value) => setState(() => _kataCari = value.trim().toLowerCase()),
                ),
                const SizedBox(height: AppSpacing.sm),
                SizedBox(
                  height: 34,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      _FilterChipButton(
                        label: 'Semua',
                        selected: _filter == _FilterChip.semua,
                        onTap: () => setState(() => _filter = _FilterChip.semua),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      _FilterChipButton(
                        label: 'Stok menipis · $jumlahMenipis',
                        variant: _ChipVariant.warning,
                        selected: _filter == _FilterChip.stokMenipis,
                        onTap: () => setState(() => _filter = _FilterChip.stokMenipis),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      _FilterChipButton(
                        label: 'Nonaktif',
                        selected: _filter == _FilterChip.nonaktif,
                        onTap: () => setState(() => _filter = _FilterChip.nonaktif),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: produkAsync.when(
              data: (items) {
                var tampil = items.where((p) {
                  if (_filter == _FilterChip.nonaktif) return !p.aktif;
                  if (_filter == _FilterChip.stokMenipis) {
                    return stokByProdukId[p.id]?.stokMenipis ?? false;
                  }
                  return true;
                });
                if (_kataCari.isNotEmpty) {
                  tampil = tampil.where((p) => p.nama.toLowerCase().contains(_kataCari));
                }
                final list = tampil.toList();

                if (list.isEmpty) {
                  return const EmptyState(
                    icon: Icons.inventory_2_outlined,
                    message: 'Belum ada produk',
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  itemCount: list.length,
                  separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, index) {
                    final produk = list[index];
                    final stok = stokByProdukId[produk.id];
                    return _ProdukRow(produk: produk, stok: stok);
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) => Center(child: Text('Gagal memuat produk: $error')),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/produk/tambah'),
        icon: const Icon(Icons.add),
        label: const Text('Produk'),
      ),
    );
  }
}

class _FilterChipButton extends StatelessWidget {
  const _FilterChipButton({
    required this.label,
    required this.selected,
    required this.onTap,
    this.variant,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final _ChipVariant? variant;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, border) = selected
        ? (AppColors.textPrimary, AppColors.surface, AppColors.textPrimary)
        : variant == _ChipVariant.warning
        ? (AppColors.warningBg, AppColors.warningTextStrong, AppColors.warningBg)
        : (AppColors.surface, AppColors.textPrimary, AppColors.borderDefault);

    return Material(
      color: bg,
      shape: StadiumBorder(side: BorderSide(color: border)),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          alignment: Alignment.center,
          child: Text(
            label,
            style: AppTypography.secondary.copyWith(fontWeight: FontWeight.w600, color: fg, fontSize: 13),
          ),
        ),
      ),
    );
  }
}

enum _ChipVariant { warning }

class _ProdukRow extends StatelessWidget {
  const _ProdukRow({required this.produk, required this.stok});

  final Produk produk;
  final StokItem? stok;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _tintUntukTipe(produk.tipe);
    final initial = AvatarInitial.fromName(produk.nama, background: bg, foreground: fg, size: 46);

    String stokLabel;
    Color stokColor;
    if (!produk.lacakStok) {
      stokLabel = '';
      stokColor = AppColors.textSecondary;
    } else if (stok == null || stok!.jumlah <= 0) {
      stokLabel = 'Habis';
      stokColor = AppColors.dangerText;
    } else if (stok!.stokMenipis) {
      stokLabel = 'Sisa ${stok!.jumlah.toStringAsFixed(0)}';
      stokColor = AppColors.warningTextStrong;
    } else {
      stokLabel = 'Stok ${stok!.jumlah.toStringAsFixed(0)}';
      stokColor = AppColors.textSecondary;
    }

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.push('/produk/tambah', extra: produk),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.borderDefault),
          ),
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              initial,
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(produk.nama, style: AppTypography.bodyEmphasis),
                    Text(_labelTipe(produk.tipe), style: AppTypography.secondary),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    produk.dijual ? _formatRupiah.format(produk.hargaJual) : '—',
                    style: AppTypography.moneyAmount,
                  ),
                  if (stokLabel.isNotEmpty)
                    Text(
                      stokLabel,
                      style: AppTypography.secondary.copyWith(
                        fontWeight: FontWeight.w600,
                        color: stokColor,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
