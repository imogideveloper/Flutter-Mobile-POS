import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/network/auth_session_store.dart';
import '../../../../core/network/dio_backend_api.dart';
import '../../../../core/providers/session_provider.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/offline_notice_banner.dart';
import '../../data/local/tables/pajak_table.dart' show PajakTipe;
import '../../domain/pajak.dart';
import '../providers/pajak_providers.dart';

const _labelTipePajak = {PajakTipe.pajak: 'Pajak', PajakTipe.service: 'Service charge'};

/// Tahap 5 C.6 - "daftar dan edit". Pajak/promo/dkk SELALU online
/// (Prinsip 1), jadi SIMPAN di sini menulis LANGSUNG ke backend (BUKAN
/// lokal lalu sync, beda dari gaya lama repository ini) - pola sama dgn
/// PengaturanOutletStrukPage. Cache lokal drift diperbarui setelah sukses
/// supaya daftar langsung terlihat tanpa menunggu sync penuh.
class PajakFormPage extends ConsumerStatefulWidget {
  const PajakFormPage({super.key, this.pajakEdit});

  final Pajak? pajakEdit;

  @override
  ConsumerState<PajakFormPage> createState() => _PajakFormPageState();
}

class _PajakFormPageState extends ConsumerState<PajakFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final _namaController = TextEditingController(text: widget.pajakEdit?.nama ?? '');
  late final _persenController =
      TextEditingController(text: widget.pajakEdit != null ? _formatPersen(widget.pajakEdit!.persen) : '');
  late final _urutanController =
      TextEditingController(text: (widget.pajakEdit?.urutan ?? 0).toString());
  late PajakTipe _tipe = widget.pajakEdit?.tipe ?? PajakTipe.pajak;
  late bool _termasukHarga = widget.pajakEdit?.termasukHarga ?? false;
  late bool _aktif = widget.pajakEdit?.aktif ?? true;
  bool _menyimpan = false;
  bool _menghapus = false;
  String? _errorServer;

  bool get _modeEdit => widget.pajakEdit != null;

  static String _formatPersen(double v) => v.truncateToDouble() == v ? v.toStringAsFixed(0) : v.toString();

  @override
  void dispose() {
    _namaController.dispose();
    _persenController.dispose();
    _urutanController.dispose();
    super.dispose();
  }

  Future<void> _simpan() async {
    if (!_formKey.currentState!.validate()) return;
    final sesi = await ref.read(authSessionStoreProvider).muat();
    if (sesi == null) {
      setState(() => _errorServer = 'Device belum pairing ke backend.');
      return;
    }

    setState(() {
      _menyimpan = true;
      _errorServer = null;
    });
    try {
      final body = {
        'nama': _namaController.text.trim(),
        'tipe': _tipe == PajakTipe.pajak ? 'pajak' : 'service',
        'persen': _persenController.text.trim(),
        'termasuk_harga': _termasukHarga,
        'urutan': int.tryParse(_urutanController.text) ?? 0,
        if (_modeEdit) 'aktif': _aktif,
      };
      final Map<String, dynamic> hasil;
      if (_modeEdit) {
        hasil = await ref.read(backendApiProvider).patchJson(
              accessToken: sesi.accessToken,
              path: '/pajak/${widget.pajakEdit!.id}',
              body: body,
            ) as Map<String, dynamic>;
      } else {
        hasil = await ref.read(backendApiProvider).postJson(
              accessToken: sesi.accessToken,
              path: '/pajak',
              body: body,
            ) as Map<String, dynamic>;
      }

      final tokoId = ref.read(currentTokoIdProvider);
      final now = DateTime.now().millisecondsSinceEpoch;
      await ref.read(pajakDaoProvider).upsertPajak(PajakCompanion.insert(
            id: hasil['id'] as String,
            tokoId: tokoId,
            nama: hasil['nama'] as String,
            tipe: Value(hasil['tipe'] == 'service' ? PajakTipe.service : PajakTipe.pajak),
            persen: double.parse(hasil['persen'].toString()),
            termasukHarga: Value(hasil['termasuk_harga'] as bool),
            urutan: Value(hasil['urutan'] as int),
            aktif: Value(hasil['aktif'] as bool),
            createdAt: now,
            updatedAt: now,
          ));

      if (mounted) context.pop();
    } catch (e) {
      setState(() => _errorServer = 'Gagal menyimpan: $e');
    } finally {
      if (mounted) setState(() => _menyimpan = false);
    }
  }

  Future<void> _hapus() async {
    final konfirmasi = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus pajak/service?'),
        content: Text('"${widget.pajakEdit!.nama}" akan dinonaktifkan. Transaksi lama tidak terpengaruh.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Hapus')),
        ],
      ),
    );
    if (konfirmasi != true) return;
    final sesi = await ref.read(authSessionStoreProvider).muat();
    if (sesi == null) return;

    setState(() => _menghapus = true);
    try {
      await ref.read(backendApiProvider).deleteJson(
            accessToken: sesi.accessToken,
            path: '/pajak/${widget.pajakEdit!.id}',
          );
      await ref.read(pajakDaoProvider).nonaktifkanLokal(widget.pajakEdit!.id);
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        showAppToast(context, message: 'Gagal menghapus: $e', variant: ToastVariant.danger);
      }
    } finally {
      if (mounted) setState(() => _menghapus = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final online = isOnlineSaat(ref);
    return Scaffold(
      appBar: AppBar(
        title: Text(_modeEdit ? 'Ubah Pajak/Service' : 'Tambah Pajak/Service'),
        actions: [
          if (_modeEdit)
            IconButton(
              key: const Key('pajakForm.hapus'),
              onPressed: _menghapus || !online ? null : _hapus,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          key: const Key('pajakForm.scrollView'),
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const OfflineNoticeBanner(),
                if (_errorServer != null) ...[
                  Text(_errorServer!, style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: AppSpacing.sm),
                ],
                TextFormField(
                  key: const Key('pajakForm.nama'),
                  controller: _namaController,
                  decoration: const InputDecoration(labelText: 'Nama (mis. PPN, Service Charge)'),
                  validator: (value) =>
                      (value == null || value.trim().isEmpty) ? 'Nama wajib diisi' : null,
                ),
                const SizedBox(height: AppSpacing.lg),
                DropdownButtonFormField<PajakTipe>(
                  initialValue: _tipe,
                  decoration: const InputDecoration(labelText: 'Tipe'),
                  items: PajakTipe.values
                      .map((tipe) => DropdownMenuItem(value: tipe, child: Text(_labelTipePajak[tipe]!)))
                      .toList(),
                  onChanged: (value) => setState(() => _tipe = value ?? _tipe),
                ),
                const SizedBox(height: AppSpacing.lg),
                TextFormField(
                  key: const Key('pajakForm.persen'),
                  controller: _persenController,
                  decoration: const InputDecoration(labelText: 'Persen (%)'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return 'Persen wajib diisi';
                    if (double.tryParse(value) == null) return 'Persen harus berupa angka';
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.lg),
                TextFormField(
                  key: const Key('pajakForm.urutan'),
                  controller: _urutanController,
                  decoration: const InputDecoration(
                    labelText: 'Urutan',
                    helperText: 'Service charge biasanya diisi urutan lebih kecil dari PPN',
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: AppSpacing.lg),
                Material(
                  type: MaterialType.transparency,
                  child: SwitchListTile(
                    key: const Key('pajakForm.termasukHarga'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Sudah termasuk di harga jual'),
                    subtitle: const Text(
                      'Kalau aktif, nilainya hanya dilaporkan, tidak ditambahkan ke total',
                    ),
                    value: _termasukHarga,
                    onChanged: (value) => setState(() => _termasukHarga = value),
                  ),
                ),
                if (_modeEdit)
                  Material(
                    type: MaterialType.transparency,
                    child: SwitchListTile(
                      key: const Key('pajakForm.aktif'),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Aktif'),
                      value: _aktif,
                      onChanged: (value) => setState(() => _aktif = value),
                    ),
                  ),
                const SizedBox(height: AppSpacing.xxxl),
                AppPrimaryButton(
                  key: const Key('pajakForm.simpan'),
                  label: _menyimpan ? 'Menyimpan...' : 'Simpan',
                  onPressed: _menyimpan || !online ? null : _simpan,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
