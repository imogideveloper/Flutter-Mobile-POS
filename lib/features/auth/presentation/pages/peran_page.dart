import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/auth_session_store.dart';
import '../../../../core/network/backend_exception.dart';
import '../../../../core/network/dio_backend_api.dart';
import '../../../../core/providers/izin_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/offline_notice_banner.dart';
import '../../domain/label_izin.dart';

String _pesanError(Object e) => e is BackendException ? e.message : '$e';

/// Daftar peran: peran bawaan (hanya lihat) dan peran buatan toko (bisa diubah/dihapus).
class PeranListPage extends ConsumerStatefulWidget {
  const PeranListPage({super.key});

  @override
  ConsumerState<PeranListPage> createState() => _PeranListPageState();
}

class _PeranListPageState extends ConsumerState<PeranListPage> {
  bool _memuat = true;
  String? _error;
  List<Map<String, dynamic>> _daftar = [];

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    setState(() {
      _memuat = true;
      _error = null;
    });
    try {
      final sesi = await ref.read(authSessionStoreProvider).muat();
      if (sesi == null) {
        _error = 'Device belum pairing ke backend.';
        return;
      }
      final data = await ref.read(backendApiProvider).getJson(accessToken: sesi.accessToken, path: '/roles') as List;
      _daftar = data.cast<Map<String, dynamic>>();
      _daftar.sort((a, b) {
        final sa = a['is_system'] == true ? 0 : 1;
        final sb = b['is_system'] == true ? 0 : 1;
        return sa != sb ? sa.compareTo(sb) : (a['nama'] as String).compareTo(b['nama'] as String);
      });
    } catch (e) {
      _error = 'Gagal memuat peran: ${_pesanError(e)}';
    } finally {
      if (mounted) setState(() => _memuat = false);
    }
  }

  Future<void> _buka(String? id) async {
    await context.push('/peran/form', extra: id);
    _muat();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Peran dan hak akses')),
      floatingActionButton: FloatingActionButton(
        key: const Key('peranList.tambah'),
        onPressed: () => _buka(null),
        tooltip: 'Tambah peran',
        child: const Icon(Icons.add),
      ),
      body: _memuat
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  children: [
                    const OfflineNoticeBanner(),
                    if (_daftar.isEmpty)
                      const EmptyState(icon: Icons.admin_panel_settings_outlined, message: 'Belum ada peran'),
                    for (final peran in _daftar) ...[
                      AppCard(
                        onTap: () => _buka(peran['id'] as String),
                        child: Row(
                          children: [
                            Icon(
                              peran['is_system'] == true ? Icons.lock_outline : Icons.admin_panel_settings_outlined,
                              color: AppColors.primary,
                            ),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(peran['nama'] as String),
                                  Text(
                                    peran['is_system'] == true ? 'Bawaan, hanya bisa dilihat' : 'Buatan toko',
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                  ],
                ),
    );
  }
}

/// Buat, ubah, atau hapus satu peran. [peranId] null = peran baru.
class PeranFormPage extends ConsumerStatefulWidget {
  const PeranFormPage({super.key, this.peranId});

  final String? peranId;

  @override
  ConsumerState<PeranFormPage> createState() => _PeranFormPageState();
}

class _PeranFormPageState extends ConsumerState<PeranFormPage> {
  final _namaController = TextEditingController();
  bool _memuat = true;
  bool _menyimpan = false;
  bool _bawaan = false;
  int _jumlahPengguna = 0;
  String? _error;
  List<Map<String, dynamic>> _katalog = [];
  final Set<String> _terpilih = {};

  bool get _baru => widget.peranId == null;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  @override
  void dispose() {
    _namaController.dispose();
    super.dispose();
  }

  Future<void> _muat() async {
    try {
      final sesi = await ref.read(authSessionStoreProvider).muat();
      if (sesi == null) {
        _error = 'Device belum pairing ke backend.';
        return;
      }
      final api = ref.read(backendApiProvider);
      _katalog = ((await api.getJson(accessToken: sesi.accessToken, path: '/izin')) as List).cast<Map<String, dynamic>>();
      if (!_baru) {
        final d = await api.getJson(accessToken: sesi.accessToken, path: '/roles/${widget.peranId}') as Map;
        _namaController.text = d['nama'] as String;
        _bawaan = d['is_system'] == true;
        _jumlahPengguna = (d['jumlah_pengguna'] as num?)?.toInt() ?? 0;
        _terpilih.addAll((d['izin_kode'] as List).cast<String>());
      }
    } catch (e) {
      _error = 'Gagal memuat peran: ${_pesanError(e)}';
    } finally {
      if (mounted) setState(() => _memuat = false);
    }
  }

  Future<void> _simpan() async {
    final nama = _namaController.text.trim();
    if (nama.isEmpty) {
      showAppToast(context, message: 'Nama peran wajib diisi', variant: ToastVariant.warning);
      return;
    }
    setState(() => _menyimpan = true);
    try {
      final sesi = await ref.read(authSessionStoreProvider).muat();
      final api = ref.read(backendApiProvider);
      final body = {'nama': nama, 'izin_kode': _terpilih.toList()..sort()};
      if (_baru) {
        await api.postJson(accessToken: sesi!.accessToken, path: '/roles', body: body);
      } else {
        await api.patchJson(accessToken: sesi!.accessToken, path: '/roles/${widget.peranId}', body: body);
      }
      if (mounted) {
        showAppToast(context, message: 'Peran disimpan', variant: ToastVariant.success);
        context.pop();
      }
    } catch (e) {
      if (mounted) showAppToast(context, message: 'Gagal menyimpan: ${_pesanError(e)}', variant: ToastVariant.danger);
    } finally {
      if (mounted) setState(() => _menyimpan = false);
    }
  }

  Future<void> _hapus() async {
    final yakin = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus peran?'),
        content: Text('Peran "${_namaController.text}" akan dihapus.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          TextButton(
            key: const Key('peranForm.hapusYa'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (yakin != true) return;
    try {
      final sesi = await ref.read(authSessionStoreProvider).muat();
      await ref.read(backendApiProvider).deleteJson(accessToken: sesi!.accessToken, path: '/roles/${widget.peranId}');
      if (mounted) {
        showAppToast(context, message: 'Peran dihapus', variant: ToastVariant.success);
        context.pop();
      }
    } catch (e) {
      if (mounted) showAppToast(context, message: _pesanError(e), variant: ToastVariant.danger);
    }
  }

  @override
  Widget build(BuildContext context) {
    final izinSaya = ref.watch(izinSayaProvider).value;
    final modul = <String, List<Map<String, dynamic>>>{};
    for (final i in _katalog) {
      modul.putIfAbsent(i['modul'] as String, () => []).add(i);
    }
    final urutan = [
      ...judulModulIzin.keys.where(modul.containsKey),
      ...modul.keys.where((m) => !judulModulIzin.containsKey(m)),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(_baru ? 'Peran baru' : (_bawaan ? 'Peran bawaan' : 'Ubah peran'))),
      body: _memuat
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  children: [
                    TextField(
                      key: const Key('peranForm.nama'),
                      controller: _namaController,
                      enabled: !_bawaan,
                      maxLength: 50,
                      decoration: const InputDecoration(labelText: 'Nama peran'),
                    ),
                    if (_bawaan)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.md),
                        child: Text(
                          'Peran bawaan tidak bisa diubah. Buat peran baru bila hak aksesnya perlu berbeda.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    for (final m in urutan) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.xs),
                        child: Text(judulModulIzin[m] ?? m, style: Theme.of(context).textTheme.titleSmall),
                      ),
                      for (final i in modul[m]!)
                        _barisIzin(i, bolehUbah: !_bawaan && (izinSaya == null || izinSaya.contains(i['kode']))),
                    ],
                    const SizedBox(height: AppSpacing.xl),
                    if (!_bawaan)
                      FilledButton(
                        key: const Key('peranForm.simpan'),
                        onPressed: _menyimpan ? null : _simpan,
                        child: Text(_menyimpan ? 'Menyimpan...' : 'Simpan'),
                      ),
                    if (!_baru && !_bawaan) ...[
                      const SizedBox(height: AppSpacing.sm),
                      OutlinedButton(
                        key: const Key('peranForm.hapus'),
                        onPressed: _jumlahPengguna > 0 ? null : _hapus,
                        child: Text(
                          _jumlahPengguna > 0 ? 'Dipakai $_jumlahPengguna karyawan, tidak bisa dihapus' : 'Hapus peran',
                        ),
                      ),
                    ],
                  ],
                ),
    );
  }

  Widget _barisIzin(Map<String, dynamic> i, {required bool bolehUbah}) {
    final kode = i['kode'] as String;
    final label = labelIzin[kode];
    return CheckboxListTile(
      key: Key('peranForm.izin.$kode'),
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      value: _terpilih.contains(kode),
      onChanged: bolehUbah
          ? (v) => setState(() {
                if (v == true) {
                  _terpilih.add(kode);
                } else {
                  _terpilih.remove(kode);
                }
              })
          : null,
      title: Text(label?.judul ?? (i['deskripsi'] as String? ?? kode)),
      subtitle: Text(label?.keterangan ?? kode),
    );
  }
}
