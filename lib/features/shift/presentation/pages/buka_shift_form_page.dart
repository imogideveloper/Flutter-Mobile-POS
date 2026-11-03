import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers/session_provider.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/rupiah_input_formatter.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_toast.dart';
import '../providers/shift_providers.dart';

const _nominalCepat = [100000, 200000, 500000];

class BukaShiftFormPage extends ConsumerStatefulWidget {
  const BukaShiftFormPage({super.key});

  @override
  ConsumerState<BukaShiftFormPage> createState() => _BukaShiftFormPageState();
}

class _BukaShiftFormPageState extends ConsumerState<BukaShiftFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _modalAwalController = TextEditingController(text: '0');
  bool _menyimpan = false;

  @override
  void dispose() {
    _modalAwalController.dispose();
    super.dispose();
  }

  Future<void> _simpan() async {
    if (!_formKey.currentState!.validate()) return;

    final penggunaId = ref.read(currentPenggunaIdProvider);
    if (penggunaId == null) {
      showAppToast(context, message: 'Silakan login dulu', variant: ToastVariant.warning);
      return;
    }

    setState(() => _menyimpan = true);
    final tokoId = ref.read(currentTokoIdProvider);
    final outletId = ref.read(currentOutletIdProvider);

    try {
      await ref.read(shiftRepositoryProvider).bukaShift(
            tokoId: tokoId,
            outletId: outletId,
            penggunaId: penggunaId,
            modalAwal: parseRupiahInput(_modalAwalController.text) ?? 0,
          );
      ref.invalidate(shiftTerbukaProvider(outletId));
      if (mounted) context.pop();
    } catch (error) {
      if (mounted) {
        showAppToast(context, message: '$error', variant: ToastVariant.danger);
      }
    } finally {
      if (mounted) setState(() => _menyimpan = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Buka shift')),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          key: const Key('bukaShiftForm.scrollView'),
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Modal awal di laci',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextFormField(
                      key: const Key('bukaShiftForm.modalAwal'),
                      controller: _modalAwalController,
                      decoration: const InputDecoration(prefixText: 'Rp '),
                      keyboardType: TextInputType.number,
                      inputFormatters: [RupiahInputFormatter()],
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                      validator: (value) {
                        if (parseRupiahInput(value ?? '') == null) return 'Modal awal wajib diisi';
                        return null;
                      },
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.sm,
                      children: [
                        for (final nominal in _nominalCepat)
                          OutlinedButton(
                            onPressed: () => setState(
                              () => _modalAwalController.text = formatRupiahDigits(nominal),
                            ),
                            child: Text('Rp${nominal ~/ 1000}.000'),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    const Text(
                      'Hitung uang tunai di laci sebelum mulai. Angka ini jadi dasar '
                      'perhitungan saat tutup shift.',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xxxl),
              AppPrimaryButton(
                label: _menyimpan ? 'Menyimpan...' : 'Mulai shift',
                onPressed: _menyimpan ? null : _simpan,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
