import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/izin_provider.dart';
import '../providers/session_provider.dart';

/// Minta otorisasi untuk aksi sensitif (void, refund, diskon manual, ubah
/// harga, hapus produk - aturan #7). Kalau pengguna yang sedang login
/// SUDAH punya izinnya, lolos tanpa nanya PIN. Kalau tidak (mis. Kasir),
/// minta PIN siapapun yang berwenang.
///
/// Return: id pengguna yang mengotorisasi (diri sendiri atau approver),
/// atau null kalau dibatalkan/ditolak.
Future<String?> mintaOtorisasi({
  required BuildContext context,
  required WidgetRef ref,
  required String kodeIzin,
  required String aksiLabel,
}) async {
  final izinService = ref.read(izinServiceProvider);
  final penggunaId = ref.read(currentPenggunaIdProvider);

  if (penggunaId != null && await izinService.hasIzin(penggunaId, kodeIzin)) {
    return penggunaId;
  }

  if (!context.mounted) return null;
  final pin = await showDialog<String>(
    context: context,
    builder: (context) => _PinDialog(aksiLabel: aksiLabel),
  );
  if (pin == null || pin.isEmpty) return null;

  final tokoId = ref.read(currentTokoIdProvider);
  final approver = await izinService.cariPenggunaUntukApproval(
    tokoId: tokoId,
    pin: pin,
    kodeIzin: kodeIzin,
  );
  return approver?.id;
}

class _PinDialog extends StatefulWidget {
  const _PinDialog({required this.aksiLabel});

  final String aksiLabel;

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  final _pinController = TextEditingController();

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Perlu approval: ${widget.aksiLabel}'),
      content: TextField(
        controller: _pinController,
        autofocus: true,
        obscureText: true,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: 'PIN owner/manajer'),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_pinController.text),
          child: const Text('Konfirmasi'),
        ),
      ],
    );
  }
}
