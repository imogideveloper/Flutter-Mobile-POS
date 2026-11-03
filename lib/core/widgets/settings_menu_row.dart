import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// Satu baris menu di halaman Lainnya/Pengaturan: label kiri, value kanan
/// (abu-abu), chevron. Dipakai berjejer di dalam satu [AppCard] per grup.
class SettingsMenuRow extends StatelessWidget {
  const SettingsMenuRow({
    super.key,
    required this.label,
    this.value,
    required this.onTap,
    this.showDivider = true,
  });

  final String label;
  final String? value;
  final VoidCallback onTap;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        decoration: showDivider
            ? const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.borderDefault)),
              )
            : null,
        child: Row(
          children: [
            Expanded(child: Text(label, style: AppTypography.bodyEmphasis)),
            if (value != null) ...[
              Text(value!, style: AppTypography.secondary),
              const SizedBox(width: AppSpacing.xs),
            ],
            const Icon(Icons.chevron_right, size: 18, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}
