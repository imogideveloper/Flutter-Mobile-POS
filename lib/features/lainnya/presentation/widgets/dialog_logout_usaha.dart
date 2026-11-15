import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/logout_usaha.dart';
import '../../../../core/widgets/app_toast.dart';

/// Konfirmasi lalu keluar dari usaha (hanya Owner; lihat LainnyaPage).
/// Bila masih ada data belum terkirim ke server, logout ditahan dan
/// pengguna diminta mencoba sync dulu - data tidak pernah dibuang diam-diam.
Future<void> tampilkanLogoutUsaha(BuildContext context, WidgetRef ref) async {
  final yakin = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      key: const Key('logoutUsaha.dialog'),
      title: const Text('Keluar dari usaha?'),
      content: const Text(
        'Perangkat ini akan dilepas dari usaha: sesi dan data lokal dihapus. '
        'Data yang sudah tersinkron tetap aman di server. '
        'Untuk memakai lagi, daftar atau masuk ulang dengan OTP.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Batal')),
        FilledButton(
          key: const Key('logoutUsaha.konfirmasi'),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Keluar dari usaha'),
        ),
      ],
    ),
  );
  if (yakin != true || !context.mounted) return;

  final hasil = await keluarDariUsaha(ref);
  if (!context.mounted) return;
  if (hasil == HasilLogoutUsaha.belumSinkron) {
    showAppToast(
      context,
      message: 'Masih ada transaksi yang belum terkirim ke server. Hubungkan internet lalu coba lagi.',
      variant: ToastVariant.warning,
    );
    return;
  }
  context.go('/');
}
