import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/providers/session_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/rupiah_input_formatter.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../transaksi/presentation/providers/transaksi_providers.dart';
import '../providers/shift_providers.dart';

final _formatRupiah = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp', decimalDigits: 0);

class TutupShiftFormPage extends ConsumerStatefulWidget {
  const TutupShiftFormPage({required this.shiftId, super.key});

  final String shiftId;

  @override
  ConsumerState<TutupShiftFormPage> createState() => _TutupShiftFormPageState();
}

class _TutupShiftFormPageState extends ConsumerState<TutupShiftFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _kasSeharusnyaController = TextEditingController();
  final _kasAktualController = TextEditingController();
  bool _menyimpan = false;

  @override
  void initState() {
    super.initState();
    _kasSeharusnyaController.addListener(_onChanged);
    _kasAktualController.addListener(_onChanged);
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    _kasSeharusnyaController.dispose();
    _kasAktualController.dispose();
    super.dispose();
  }

  int? get _selisih {
    final seharusnya = parseRupiahInput(_kasSeharusnyaController.text);
    final aktual = parseRupiahInput(_kasAktualController.text);
    if (seharusnya == null || aktual == null) return null;
    return aktual - seharusnya;
  }

  /// F3.E.5 - pesanan tersimpan (open bill) TIDAK terikat shift_id (baru
  /// dapat shift begitu benar2 dibayar), jadi tidak ada "pindahkan ke
  /// shift berikutnya" yang perlu dilakukan sungguhan - murni peringatan
  /// supaya kasir tidak lupa masih ada draft yang menggantung.
  Future<bool> _konfirmasiJikaAdaPesananTersimpan() async {
    final jumlah = ref.read(pesananTersimpanProvider).value?.length ?? 0;
    if (jumlah == 0) return true;
    final lanjut = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Masih ada pesanan tersimpan'),
        content: Text(
          'Ada $jumlah pesanan tersimpan (open bill) yang belum dibayar/dibatalkan. '
          'Pesanan itu tetap tersimpan dan bisa dilanjutkan di shift berikutnya - tetap tutup shift sekarang?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Tetap tutup shift')),
        ],
      ),
    );
    return lanjut ?? false;
  }

  Future<void> _simpan() async {
    if (!_formKey.currentState!.validate()) return;
    if (!await _konfirmasiJikaAdaPesananTersimpan()) return;
    if (!mounted) return;

    setState(() => _menyimpan = true);
    final outletId = ref.read(currentOutletIdProvider);

    try {
      await ref.read(shiftRepositoryProvider).tutupShift(
            shiftId: widget.shiftId,
            kasSeharusnya: parseRupiahInput(_kasSeharusnyaController.text) ?? 0,
            kasAktual: parseRupiahInput(_kasAktualController.text) ?? 0,
          );
      ref.invalidate(shiftTerbukaProvider(outletId));
      if (mounted) context.pop();
    } finally {
      if (mounted) setState(() => _menyimpan = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selisih = _selisih;
    // Dijaga tetap aktif (watch, bukan cuma read di _simpan) supaya
    // pesananTersimpanProvider sudah punya data terbaru begitu kasir
    // menekan tombol Tutup shift, bukan AsyncLoading kosong.
    ref.watch(pesananTersimpanProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Tutup shift')),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          key: const Key('tutupShiftForm.scrollView'),
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Belum dihitung otomatis dari rekap penjualan+kas shift
                    // (butuh agregasi transaksi per metode bayar) - masih
                    // input manual, lihat catatan risiko ringkasan tugas.
                    TextFormField(
                      key: const Key('tutupShiftForm.kasSeharusnya'),
                      controller: _kasSeharusnyaController,
                      decoration: const InputDecoration(labelText: 'Kas seharusnya (Rp)'),
                      keyboardType: TextInputType.number,
                      inputFormatters: [RupiahInputFormatter()],
                      validator: (value) {
                        if (parseRupiahInput(value ?? '') == null) return 'Wajib diisi';
                        return null;
                      },
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    TextFormField(
                      key: const Key('tutupShiftForm.kasAktual'),
                      controller: _kasAktualController,
                      decoration: const InputDecoration(labelText: 'Kas aktual di laci (Rp)'),
                      keyboardType: TextInputType.number,
                      inputFormatters: [RupiahInputFormatter()],
                      validator: (value) {
                        if (parseRupiahInput(value ?? '') == null) return 'Wajib diisi';
                        return null;
                      },
                    ),
                  ],
                ),
              ),
              if (selisih != null && selisih != 0) ...[
                const SizedBox(height: AppSpacing.lg),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.md,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.warningBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        selisih > 0 ? 'Selisih lebih' : 'Selisih kurang',
                        style: AppTypography.bodyEmphasis.copyWith(color: AppColors.warningTextStrong),
                      ),
                      Text(
                        _formatRupiah.format(selisih),
                        style: AppTypography.bodyEmphasis.copyWith(color: AppColors.warningTextStrong),
                      ),
                    ],
                  ),
                ),
              ] else if (selisih == 0) ...[
                const SizedBox(height: AppSpacing.lg),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: AppBadge(label: 'Kas sesuai', variant: BadgeVariant.success),
                ),
              ],
              const SizedBox(height: AppSpacing.xxxl),
              AppPrimaryButton(
                key: const Key('tutupShiftForm.submit'),
                label: _menyimpan ? 'Menyimpan...' : 'Tutup shift',
                onPressed: _menyimpan ? null : _simpan,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
