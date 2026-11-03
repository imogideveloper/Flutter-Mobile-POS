import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers/session_provider.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/rupiah_input_formatter.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../data/local/tables/kas_shift_table.dart' show KasShiftJenis;
import '../providers/shift_providers.dart';

const _labelJenisKas = {KasShiftJenis.masuk: 'Kas masuk', KasShiftJenis.keluar: 'Kas keluar'};

class CatatKasFormPage extends ConsumerStatefulWidget {
  const CatatKasFormPage({required this.shiftId, super.key});

  final String shiftId;

  @override
  ConsumerState<CatatKasFormPage> createState() => _CatatKasFormPageState();
}

class _CatatKasFormPageState extends ConsumerState<CatatKasFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _jumlahController = TextEditingController();
  final _keteranganController = TextEditingController();
  KasShiftJenis _jenis = KasShiftJenis.keluar;
  bool _menyimpan = false;

  @override
  void dispose() {
    _jumlahController.dispose();
    _keteranganController.dispose();
    super.dispose();
  }

  Future<void> _simpan() async {
    if (!_formKey.currentState!.validate()) return;

    final dibuatOleh = ref.read(currentPenggunaIdProvider);
    if (dibuatOleh == null) {
      showAppToast(context, message: 'Silakan login dulu', variant: ToastVariant.warning);
      return;
    }

    setState(() => _menyimpan = true);

    try {
      await ref.read(shiftRepositoryProvider).catatKasMasukKeluar(
            shiftId: widget.shiftId,
            jenis: _jenis,
            jumlah: parseRupiahInput(_jumlahController.text) ?? 0,
            keterangan: _keteranganController.text.trim(),
            dibuatOleh: dibuatOleh,
          );
      if (mounted) context.pop();
    } finally {
      if (mounted) setState(() => _menyimpan = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Catat Kas Masuk/Keluar')),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          key: const Key('catatKasForm.scrollView'),
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SegmentedButton<KasShiftJenis>(
                  segments: KasShiftJenis.values
                      .map((j) => ButtonSegment(value: j, label: Text(_labelJenisKas[j]!)))
                      .toList(),
                  selected: {_jenis},
                  onSelectionChanged: (value) => setState(() => _jenis = value.first),
                ),
                const SizedBox(height: AppSpacing.lg),
                TextFormField(
                  key: const Key('catatKasForm.jumlah'),
                  controller: _jumlahController,
                  decoration: const InputDecoration(labelText: 'Jumlah (Rp)'),
                  keyboardType: TextInputType.number,
                  inputFormatters: [RupiahInputFormatter()],
                  validator: (value) {
                    if (parseRupiahInput(value ?? '') == null) return 'Jumlah wajib diisi';
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.lg),
                TextFormField(
                  key: const Key('catatKasForm.keterangan'),
                  controller: _keteranganController,
                  decoration: const InputDecoration(labelText: 'Keterangan'),
                  validator: (value) =>
                      (value == null || value.trim().isEmpty) ? 'Keterangan wajib diisi' : null,
                ),
                const SizedBox(height: AppSpacing.xxxl),
                AppPrimaryButton(
                  label: _menyimpan ? 'Menyimpan...' : 'Simpan',
                  onPressed: _menyimpan ? null : _simpan,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
