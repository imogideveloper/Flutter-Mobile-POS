import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/auth/pin_approval.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/rupiah_input_formatter.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../domain/item_keranjang.dart';
import '../providers/keranjang_provider.dart';

final _rupiah = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp', decimalDigits: 0);

/// Persen pada tombol cepat diskon manual (IMOGI no. 3).
const persenDiskonCepat = [5, 10, 15, 20];

/// Sheet diskon manual per item: tombol cepat persen, isian persen/nominal
/// sendiri, dan hapus diskon. Menerapkan diskon butuh izin `transaksi.diskon`
/// atau PIN approver (aturan #7) - tanpa itu diskon tidak dipasang.
Future<void> tampilkanDiskonItem(BuildContext context, ItemKeranjang item) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => _DiskonItemSheet(item: item),
  );
}

class _DiskonItemSheet extends ConsumerStatefulWidget {
  const _DiskonItemSheet({required this.item});

  final ItemKeranjang item;

  @override
  ConsumerState<_DiskonItemSheet> createState() => _DiskonItemSheetState();
}

class _DiskonItemSheetState extends ConsumerState<_DiskonItemSheet> {
  final _persenController = TextEditingController();
  final _nominalController = TextEditingController();

  @override
  void dispose() {
    _persenController.dispose();
    _nominalController.dispose();
    super.dispose();
  }

  Future<void> _terapkan({int? persen, int nominal = 0}) async {
    final item = widget.item;
    final nilaiAkhir = persen != null ? (item.subtotal * persen / 100).round() : nominal;
    if (persen != null && (persen <= 0 || persen > 100)) {
      showAppToast(context, message: 'Persen diskon harus antara 1 dan 100', variant: ToastVariant.warning);
      return;
    }
    if (nilaiAkhir <= 0) {
      showAppToast(context, message: 'Isi nilai diskon', variant: ToastVariant.warning);
      return;
    }
    if (nilaiAkhir > item.subtotal) {
      showAppToast(
        context,
        message: 'Diskon melebihi nilai baris (${_rupiah.format(item.subtotal)})',
        variant: ToastVariant.warning,
      );
      return;
    }

    final penyetuju = await mintaOtorisasi(
      context: context,
      ref: ref,
      kodeIzin: 'transaksi.diskon',
      aksiLabel: 'Diskon manual ${item.namaProduk}',
    );
    if (penyetuju == null) {
      if (mounted) {
        showAppToast(context, message: 'Diskon tidak disetujui', variant: ToastVariant.warning);
      }
      return;
    }
    ref.read(keranjangProvider.notifier).aturDiskon(
          item.kunciBaris,
          persen: persen,
          nominal: nominal,
          disetujuiOleh: penyetuju,
        );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xl + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          key: const Key('diskonItem.sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Diskon ${item.namaProduk}', style: AppTypography.cardTitle),
            Text('Nilai baris ${_rupiah.format(item.subtotal)}', style: AppTypography.secondary),
            const SizedBox(height: AppSpacing.lg),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final p in persenDiskonCepat)
                  OutlinedButton(
                    key: Key('diskonItem.cepat.$p'),
                    onPressed: () => _terapkan(persen: p),
                    child: Text('$p%'),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('diskonItem.persen'),
                    controller: _persenController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Persen (%)'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                FilledButton(
                  key: const Key('diskonItem.terapkanPersen'),
                  onPressed: () => _terapkan(persen: int.tryParse(_persenController.text.trim())),
                  child: const Text('Pasang'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('diskonItem.nominal'),
                    controller: _nominalController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Nominal (Rp)'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                FilledButton(
                  key: const Key('diskonItem.terapkanNominal'),
                  onPressed: () => _terapkan(nominal: parseRupiahInput(_nominalController.text) ?? 0),
                  child: const Text('Pasang'),
                ),
              ],
            ),
            if (item.adaDiskonManual) ...[
              const SizedBox(height: AppSpacing.lg),
              TextButton(
                key: const Key('diskonItem.hapus'),
                onPressed: () {
                  ref.read(keranjangProvider.notifier).hapusDiskon(item.kunciBaris);
                  Navigator.of(context).pop();
                },
                child: const Text('Hapus diskon'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
