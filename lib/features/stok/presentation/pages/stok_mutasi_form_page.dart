import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers/session_provider.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../produk/domain/produk.dart';
import '../../../produk/presentation/providers/produk_providers.dart';
import '../../data/local/tables/mutasi_stok_table.dart' show MutasiJenis;
import '../providers/stok_providers.dart';

const _labelJenisMutasi = {
  MutasiJenis.stokAwal: 'Stok awal',
  MutasiJenis.pembelian: 'Pembelian',
  MutasiJenis.penjualan: 'Penjualan',
  MutasiJenis.refund: 'Refund',
  MutasiJenis.voidTransaksi: 'Void',
  MutasiJenis.opname: 'Opname',
  MutasiJenis.transferMasuk: 'Transfer masuk',
  MutasiJenis.transferKeluar: 'Transfer keluar',
  MutasiJenis.penyesuaian: 'Penyesuaian',
  MutasiJenis.produksi: 'Produksi',
};

class StokMutasiFormPage extends ConsumerStatefulWidget {
  const StokMutasiFormPage({super.key});

  @override
  ConsumerState<StokMutasiFormPage> createState() => _StokMutasiFormPageState();
}

class _StokMutasiFormPageState extends ConsumerState<StokMutasiFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _qtyController = TextEditingController();
  final _catatanController = TextEditingController();
  Produk? _produk;
  MutasiJenis _jenis = MutasiJenis.penyesuaian;
  bool _menyimpan = false;

  @override
  void dispose() {
    _qtyController.dispose();
    _catatanController.dispose();
    super.dispose();
  }

  Future<void> _simpan() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _menyimpan = true);
    try {
      final tokoId = ref.read(currentTokoIdProvider);
      final outletId = ref.read(currentOutletIdProvider);
      await ref.read(stokRepositoryProvider).catatMutasi(
            tokoId: tokoId,
            outletId: outletId,
            produkId: _produk!.id,
            jenis: _jenis,
            qty: double.parse(_qtyController.text),
            catatan: _catatanController.text.trim().isEmpty
                ? null
                : _catatanController.text.trim(),
          );
      if (mounted) context.pop();
    } finally {
      if (mounted) setState(() => _menyimpan = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final produkAktif = ref.watch(produkAktifProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Catat Mutasi Stok')),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          key: const Key('stokMutasiForm.scrollView'),
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                produkAktif.when(
                  data: (items) => DropdownButtonFormField<Produk>(
                    key: const Key('stokMutasiForm.produk'),
                    initialValue: _produk,
                    decoration: const InputDecoration(labelText: 'Produk'),
                    items: items
                        .map((p) => DropdownMenuItem(value: p, child: Text(p.nama)))
                        .toList(),
                    onChanged: (value) => setState(() => _produk = value),
                    validator: (value) => value == null ? 'Pilih produk' : null,
                  ),
                  loading: () => const LinearProgressIndicator(),
                  error: (error, stackTrace) => Text('Gagal memuat produk: $error'),
                ),
                const SizedBox(height: AppSpacing.lg),
                DropdownButtonFormField<MutasiJenis>(
                  initialValue: _jenis,
                  decoration: const InputDecoration(labelText: 'Jenis mutasi'),
                  items: MutasiJenis.values
                      .map((j) => DropdownMenuItem(value: j, child: Text(_labelJenisMutasi[j]!)))
                      .toList(),
                  onChanged: (value) => setState(() => _jenis = value ?? _jenis),
                ),
                const SizedBox(height: AppSpacing.lg),
                TextFormField(
                  controller: _qtyController,
                  decoration: const InputDecoration(
                    labelText: 'Qty',
                    helperText: 'Positif menambah saldo, negatif mengurangi',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return 'Qty wajib diisi';
                    if (double.tryParse(value) == null) return 'Qty harus berupa angka';
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.lg),
                TextFormField(
                  controller: _catatanController,
                  decoration: const InputDecoration(labelText: 'Catatan (opsional)'),
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
