import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/network/auth_session_store.dart';
import '../../../../core/network/dio_backend_api.dart';
import '../../../../core/providers/session_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/offline_notice_banner.dart';
import '../../domain/kategori.dart';
import '../providers/produk_providers.dart' show produkDaoProvider;

/// Tambah/ubah kategori produk - online-direct (pola sama dgn
/// pajak_form_page.dart): simpan LANGSUNG ke backend, cache lokal
/// diperbarui sesudahnya supaya daftar langsung terlihat.
class KategoriFormPage extends ConsumerStatefulWidget {
  const KategoriFormPage({super.key, this.kategoriEdit});

  final Kategori? kategoriEdit;

  @override
  ConsumerState<KategoriFormPage> createState() => _KategoriFormPageState();
}

/// Palet warna pilihan - cukup segelintir warna khas (bukan color picker
/// bebas) biar daftar kategori tetap enak dilihat & konsisten.
const _paletWarna = [
  '#0F6E58', // teal (primary)
  '#9A4A07', // amber
  '#B42318', // merah
  '#2F3E7A', // indigo
  '#6B4A2B', // coklat
  '#5F6B66', // abu
];

class _KategoriFormPageState extends ConsumerState<KategoriFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final _namaController = TextEditingController(text: widget.kategoriEdit?.nama ?? '');
  late final _urutanController =
      TextEditingController(text: (widget.kategoriEdit?.urutan ?? 0).toString());
  late String _warna = widget.kategoriEdit?.warna ?? _paletWarna.first;
  late bool _masukTiketDapur = widget.kategoriEdit?.masukTiketDapur ?? true;
  bool _menyimpan = false;
  bool _menghapus = false;
  String? _errorServer;

  bool get _modeEdit => widget.kategoriEdit != null;

  @override
  void dispose() {
    _namaController.dispose();
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
        'warna': _warna,
        'masuk_tiket_dapur': _masukTiketDapur,
        'urutan': int.tryParse(_urutanController.text) ?? 0,
      };
      final Map<String, dynamic> hasil;
      if (_modeEdit) {
        hasil = await ref.read(backendApiProvider).patchJson(
              accessToken: sesi.accessToken,
              path: '/kategori/${widget.kategoriEdit!.id}',
              body: body,
            ) as Map<String, dynamic>;
      } else {
        hasil = await ref.read(backendApiProvider).postJson(
              accessToken: sesi.accessToken,
              path: '/kategori',
              body: body,
            ) as Map<String, dynamic>;
      }

      final tokoId = ref.read(currentTokoIdProvider);
      final now = DateTime.now().millisecondsSinceEpoch;
      await ref.read(produkDaoProvider).upsertKategori(KategoriCompanion.insert(
            id: hasil['id'] as String,
            tokoId: tokoId,
            nama: hasil['nama'] as String,
            warna: Value(hasil['warna'] as String?),
            urutan: Value(hasil['urutan'] as int),
            masukTiketDapur: Value((hasil['masuk_tiket_dapur'] as bool?) ?? _masukTiketDapur),
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
        title: const Text('Hapus kategori?'),
        content: Text(
          '"${widget.kategoriEdit!.nama}" akan dihapus. Produk yang masih memakainya tidak terpengaruh.',
        ),
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
            path: '/kategori/${widget.kategoriEdit!.id}',
          );
      await ref.read(produkDaoProvider).hapusKategoriLokal(widget.kategoriEdit!.id);
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
        title: Text(_modeEdit ? 'Ubah kategori' : 'Tambah kategori'),
        actions: [
          if (_modeEdit)
            IconButton(
              key: const Key('kategoriForm.hapus'),
              onPressed: _menghapus || !online ? null : _hapus,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          key: const Key('kategoriForm.scrollView'),
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const OfflineNoticeBanner(),
                if (_errorServer != null) ...[
                  Text(_errorServer!, style: const TextStyle(color: AppColors.dangerText)),
                  const SizedBox(height: AppSpacing.sm),
                ],
                TextFormField(
                  key: const Key('kategoriForm.nama'),
                  controller: _namaController,
                  decoration: const InputDecoration(labelText: 'Nama kategori (mis. Minuman)'),
                  validator: (value) =>
                      (value == null || value.trim().isEmpty) ? 'Nama wajib diisi' : null,
                ),
                const SizedBox(height: AppSpacing.lg),
                const Text('Warna'),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  children: [
                    for (final warna in _paletWarna)
                      GestureDetector(
                        key: Key('kategoriForm.warna.$warna'),
                        onTap: () => setState(() => _warna = warna),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: Color(int.parse(warna.replaceFirst('#', '0xFF'))),
                            shape: BoxShape.circle,
                            border: _warna == warna
                                ? Border.all(color: AppColors.textPrimary, width: 2)
                                : null,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                TextFormField(
                  key: const Key('kategoriForm.urutan'),
                  controller: _urutanController,
                  decoration: const InputDecoration(labelText: 'Urutan tampil'),
                  keyboardType: TextInputType.number,
                ),
                SwitchListTile(
                  key: const Key('kategoriForm.masukTiketDapur'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Masuk tiket dapur'),
                  subtitle: const Text('Matikan untuk kategori yang tidak perlu diteruskan ke dapur/bar'),
                  value: _masukTiketDapur,
                  onChanged: (v) => setState(() => _masukTiketDapur = v),
                ),
                const SizedBox(height: AppSpacing.xxxl),
                AppPrimaryButton(
                  key: const Key('kategoriForm.simpan'),
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
