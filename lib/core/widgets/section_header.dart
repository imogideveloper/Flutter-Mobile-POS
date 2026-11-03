import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// Judul grup uppercase abu-abu, dipakai di halaman Lainnya
/// (mis. "OPERASIONAL", "TOKO", "AKUN").
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.xs, bottom: AppSpacing.xs),
      child: Text(label.toUpperCase(), style: AppTypography.labelUppercase),
    );
  }
}
