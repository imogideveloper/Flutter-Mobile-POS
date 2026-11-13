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
import '../../domain/pelanggan.dart';
import '../../domain/ulang_tahun.dart';
import '../providers/pelanggan_providers.dart';
import 'pelanggan_form_page.dart';

final _formatRupiah = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp', decimalDigits: 0);

/// Sesuai mockup "Pelanggan": search, kartu statistik ringkas, list member
/// dgn avatar inisial + poin, FAB tambah. "Baru bulan ini"/"Ultah minggu
/// ini" di mockup asli DIHILANGKAN - butuh createdAt/tanggal_lahir yang
/// belum ada di domain Pelanggan saat ini (TODO kalau kolom itu ditambah).
class PelangganListPage extends ConsumerStatefulWidget {
  const PelangganListPage({super.key});

  @override
  ConsumerState<PelangganListPage> createState() => _PelangganListPageState();
}

class _PelangganListPageState extends ConsumerState<PelangganListPage> {
  final _cariController = TextEditingController();
  String _kata = '';

  @override
  void dispose() {
    _cariController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pelangganAsync = ref.watch(pelangganAktifProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pelanggan'),
        actions: [
          IconButton(
            tooltip: 'Piutang',
            icon: const Icon(Icons.receipt_long_outlined),
            onPressed: () => context.push('/piutang'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (context) => const PelangganFormPage()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Pelanggan'),
      ),
      body: pelangganAsync.when(
        data: (semua) {
          final total = semua.length;
          final totalPoin = semua.fold<int>(0, (a, b) => a + b.poin);
          final kata = _kata.trim().toLowerCase();
          final hasil = kata.isEmpty
              ? semua
              : semua
                  .where((p) =>
                      p.nama.toLowerCase().contains(kata) ||
                      (p.noHp ?? '').contains(kata))
                  .toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xl, AppSpacing.md, AppSpacing.xl, 0),
                child: TextField(
                  controller: _cariController,
                  onChanged: (value) => setState(() => _kata = value),
                  decoration: const InputDecoration(
                    hintText: 'Nama atau nomor HP',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Row(
                  children: [
                    Expanded(child: _StatCard(label: 'Member', value: '$total')),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: _StatCard(label: 'Total poin beredar', value: '$totalPoin')),
                  ],
                ),
              ),
              Expanded(
                child: hasil.isEmpty
                    ? const EmptyState(
                        icon: Icons.people_outline,
                        message: 'Belum ada pelanggan.\nTambah pelanggan pertama lewat tombol di bawah.',
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(
                            AppSpacing.xl, 0, AppSpacing.xl, 88),
                        itemCount: hasil.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: AppSpacing.sm),
                        itemBuilder: (context, index) => _PelangganRow(pelanggan: hasil[index]),
                      ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(child: Text('Gagal memuat pelanggan: $error')),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTypography.secondary.copyWith(fontSize: 11)),
          const SizedBox(height: 2),
          Text(value, style: AppTypography.cardTitle),
        ],
      ),
    );
  }
}

class _PelangganRow extends StatelessWidget {
  const _PelangganRow({required this.pelanggan});

  final Pelanggan pelanggan;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (context) => PelangganFormPage(pelangganEdit: pelanggan)),
      ),
      child: Row(
        children: [
          AvatarInitial.fromName(pelanggan.nama),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(pelanggan.nama, style: AppTypography.bodyEmphasis),
                if (pelanggan.noHp != null)
                  Text(pelanggan.noHp!, style: AppTypography.secondary),
                if (ulangTahunHariIni(pelanggan.tanggalLahir, DateTime.now()))
                  Row(
                    key: Key('pelangganList.ulangTahun.${pelanggan.id}'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cake_outlined, size: 14, color: AppColors.warningTextStrong),
                      const SizedBox(width: 4),
                      Text(
                        'Ulang tahun hari ini',
                        style: AppTypography.secondary.copyWith(
                          color: AppColors.warningTextStrong,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${pelanggan.poin} poin',
                  style: AppTypography.bodyEmphasis.copyWith(color: AppColors.primaryDark)),
              Text(_formatRupiah.format(pelanggan.totalBelanja),
                  style: AppTypography.secondary.copyWith(fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }
}
