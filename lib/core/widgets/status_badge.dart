import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

enum BadgeVariant { success, warning, danger, info, neutral }

/// Pill badge (radius 999) untuk status: "Pro", "stok menipis", "gagal", dst.
class AppBadge extends StatelessWidget {
  const AppBadge({super.key, required this.label, this.variant = BadgeVariant.neutral});

  final String label;
  final BadgeVariant variant;

  (Color bg, Color fg) get _colors => switch (variant) {
    BadgeVariant.success => (AppColors.primaryTint, AppColors.primaryDark),
    BadgeVariant.warning => (AppColors.warningBg, AppColors.warningText),
    BadgeVariant.danger => (AppColors.dangerBg, AppColors.dangerText),
    BadgeVariant.info => (AppColors.indigoBg, AppColors.indigoText),
    BadgeVariant.neutral => (AppColors.borderDefault, AppColors.textSecondary),
  };

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(
        label,
        style: AppTypography.secondary.copyWith(
          color: fg,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
