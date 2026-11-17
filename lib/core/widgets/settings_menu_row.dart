import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// Satu baris menu di halaman Lainnya/Pengaturan: ikon (opsional) di kiri, label, value kanan
/// (abu-abu), chevron. Dipakai berjejer di dalam satu [AppCard] per grup.
class SettingsMenuRow extends StatelessWidget {
  const SettingsMenuRow({
    super.key,
    required this.label,
    this.value,
    this.ikon,
    required this.onTap,
    this.showDivider = true,
  });

  final String label;
  final String? value;
  final IconData? ikon;
  final VoidCallback onTap;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
        decoration: showDivider
            ? const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.borderDefault)),
              )
            : null,
        child: Row(
          children: [
            if (ikon != null) ...[
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.primaryTint,
                  borderRadius: BorderRadius.circular(AppRadius.sm - 2),
                ),
                child: Icon(ikon, size: 18, color: AppColors.primary),
              ),
              const SizedBox(width: AppSpacing.md),
            ],
            Expanded(child: Text(label, style: AppTypography.bodyEmphasis)),
            if (value != null) ...[
              // Dibatasi lebarnya (bukan Flexible) supaya label tidak ikut terhimpit separuh baris.
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 130),
                child: Text(value!, style: AppTypography.secondary, overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: AppSpacing.xs),
            ],
            const Icon(Icons.chevron_right, size: 18, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}
