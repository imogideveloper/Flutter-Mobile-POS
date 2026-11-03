import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/connectivity_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Tahap 5 - Prinsip 1: dipakai SEMUA layar kelola data master (produk,
/// promo, pajak, pelanggan, karyawan, pengaturan) yang sifatnya online-only
/// (mencegah konflik data master antar HP). `ref.watch(isOnlineProvider)`
/// gagal/loading dianggap online (fail-open) supaya tidak nge-flicker
/// nonaktif saat provider baru pertama kali emit.
bool isOnlineSaat(WidgetRef ref) => ref.watch(isOnlineProvider).value ?? true;

/// Banner peringatan - taruh di atas form kelola data master, SEBELUM
/// field-field form-nya. Tombol "Simpan" di layar yang sama wajib
/// `onPressed: isOnlineSaat(ref) ? _simpan : null`.
class OfflineNoticeBanner extends ConsumerWidget {
  const OfflineNoticeBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (isOnlineSaat(ref)) return const SizedBox.shrink();
    return Container(
      key: const Key('offlineNotice.banner'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: AppSpacing.lg),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.warningBg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.wifi_off_outlined, size: 18, color: AppColors.warningText),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Butuh internet untuk mengubah pengaturan',
              style: TextStyle(color: AppColors.warningText, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
