import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// Stepper qty bulat 36x36 sesuai mockup Keranjang: tombol kurang outline,
/// tombol tambah berlatar hijau muda.
class QtyStepper extends StatelessWidget {
  const QtyStepper({
    super.key,
    required this.qty,
    required this.onIncrement,
    required this.onDecrement,
    this.onQtyTap,
  });

  final num qty;
  final VoidCallback onIncrement;
  final VoidCallback? onDecrement;

  /// Bila diisi, angka jumlah bisa diketuk untuk mengisi jumlah manual.
  final VoidCallback? onQtyTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StepperButton(
          icon: Icons.remove,
          background: AppColors.surface,
          foreground: AppColors.textPrimary,
          border: AppColors.borderStrong,
          onTap: onDecrement,
          semanticLabel: 'Kurangi',
        ),
        InkWell(
          key: const Key('qty.angka'),
          onTap: onQtyTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            constraints: const BoxConstraints(minWidth: 32),
            height: 36,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              qty % 1 == 0 ? qty.toStringAsFixed(0) : qty.toString(),
              textAlign: TextAlign.center,
              style: AppTypography.moneyAmount.copyWith(fontSize: 15),
            ),
          ),
        ),
        _StepperButton(
          icon: Icons.add,
          background: AppColors.primaryTint,
          foreground: AppColors.primaryDark,
          border: null,
          onTap: onIncrement,
          semanticLabel: 'Tambah',
        ),
      ],
    );
  }
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({
    required this.icon,
    required this.background,
    required this.foreground,
    required this.border,
    required this.onTap,
    required this.semanticLabel,
  });

  final IconData icon;
  final Color background;
  final Color foreground;
  final Color? border;
  final VoidCallback? onTap;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: onTap == null ? background.withValues(alpha: 0.5) : background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: border == null ? BorderSide.none : BorderSide(color: border!),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(icon, size: 16, color: foreground, semanticLabel: semanticLabel),
        ),
      ),
    );
  }
}
