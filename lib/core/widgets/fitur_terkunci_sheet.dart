import 'package:flutter/material.dart';

import '../network/nama_fitur.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'app_button.dart';

/// Dipanggil dari 2 tempat (lihat fitur_terkunci_event.dart): widget
/// [FiturTerkunci] saat ditekan langsung, dan listener global di
/// main.dart saat backend balas 403 `fitur_terkunci`. Isi & tampilan
/// SENGAJA sama persis di kedua jalur - pengguna tidak perlu tahu
/// apakah ini dicegah di HP atau ditolak server.
Future<void> tampilkanFiturTerkunciSheet(
  BuildContext context, {
  required String fitur,
  String? paketMinimal,
}) {
  final nama = namaTampilanFitur(fitur);
  return showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.warningBg,
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.lock_outline, color: AppColors.warningTextStrong),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(nama, style: AppTypography.cardTitle),
            const SizedBox(height: AppSpacing.xs),
            Text(
              paketMinimal != null
                  ? 'Tersedia di paket $paketMinimal. Upgrade paket toko kamu untuk membuka fitur ini.'
                  : 'Fitur ini belum tersedia di paket toko kamu saat ini.',
              style: AppTypography.secondary,
            ),
            const SizedBox(height: AppSpacing.xl),
            AppPrimaryButton(
              label: 'Tutup',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      );
    },
  );
}
