import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/providers/session_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../domain/shift.dart';
import '../providers/shift_providers.dart';

final _formatRupiah = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp', decimalDigits: 0);
final _formatWaktu = DateFormat('dd/MM/yyyy HH:mm');

class ShiftPage extends ConsumerWidget {
  const ShiftPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final outletId = ref.watch(currentOutletIdProvider);
    final shiftAktif = ref.watch(shiftTerbukaProvider(outletId));

    return Scaffold(
      appBar: AppBar(title: const Text('Shift')),
      body: shiftAktif.when(
        data: (shift) =>
            shift == null ? const _ShiftTertutup() : _ShiftTerbuka(shift: shift),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(child: Text('Gagal memuat shift: $error')),
      ),
    );
  }
}

class _ShiftTertutup extends StatelessWidget {
  const _ShiftTertutup();

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.schedule_outlined,
      message: 'Tidak ada shift terbuka di outlet ini',
      action: AppPrimaryButton(
        label: 'Buka Shift',
        onPressed: () => context.push('/shift/buka'),
      ),
    );
  }
}

class _ShiftTerbuka extends ConsumerWidget {
  const _ShiftTerbuka({required this.shift});

  final Shift shift;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dibukaPada = DateTime.fromMillisecondsSinceEpoch(shift.dibukaPada, isUtc: true).toLocal();
    final namaKasir = ref.watch(namaPenggunaProvider(shift.penggunaId)).value ?? '-';

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text('Shift sedang berjalan', style: AppTypography.cardTitle),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                _BarisInfo(label: 'Kasir', value: namaKasir, key: const Key('shiftPage.namaKasir')),
                const SizedBox(height: AppSpacing.xs),
                _BarisInfo(label: 'Dibuka', value: _formatWaktu.format(dibukaPada)),
                const SizedBox(height: AppSpacing.xs),
                _BarisInfo(label: 'Modal awal', value: _formatRupiah.format(shift.modalAwal)),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          AppPrimaryButton(
            label: 'Catat Kas Masuk/Keluar',
            onPressed: () => context.push('/shift/kas', extra: shift.id),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppSecondaryButton(
            label: 'Tutup Shift',
            fullWidth: true,
            onPressed: () => context.push('/shift/tutup', extra: shift.id),
          ),
        ],
      ),
    );
  }
}

class _BarisInfo extends StatelessWidget {
  const _BarisInfo({required this.label, required this.value, super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppTypography.secondary),
        Text(value, style: AppTypography.bodyEmphasis),
      ],
    );
  }
}
