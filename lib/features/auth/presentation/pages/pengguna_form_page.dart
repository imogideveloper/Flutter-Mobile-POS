import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/pin_hash.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/pengguna_dao.dart';
import '../../../../core/network/auth_session_store.dart';
import '../../../../core/network/dio_backend_api.dart';
import '../../../../core/providers/database_provider.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/offline_notice_banner.dart';

final _penggunaDaoProvider = Provider<PenggunaDao>((ref) => ref.watch(appDatabaseProvider).penggunaDao);

/// Tahap 5b (desain #1/#2 "Lengkapi juga") - edit/tambah karyawan ONLINE
/// (server CRUD), termasuk akses outlet (sekarang bisa dibangun krn
/// karyawan ADA di server). Setelah sukses, cache lokal (dibaca
/// login_page.dart) ditulis langsung - tidak perlu menunggu sync pull
/// penuh berikutnya.
class PenggunaFormPage extends ConsumerStatefulWidget {
  const PenggunaFormPage({super.key, this.penggunaEdit});

  final Map<String, dynamic>? penggunaEdit;

  @override
  ConsumerState<PenggunaFormPage> createState() => _PenggunaFormPageState();
}

class _PenggunaFormPageState extends ConsumerState<PenggunaFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final _namaController = TextEditingController(text: widget.penggunaEdit?['nama'] as String? ?? '');
  late final _pinController = TextEditingController();
  String? _roleId;
  late bool _aktif = widget.penggunaEdit?['aktif'] as bool? ?? true;
  Set<String> _outletIdsTerpilih = {};
  bool _memuat = true;
  bool _menyimpan = false;
  bool _menghapus = false;
  String? _error;
  List<Map<String, dynamic>> _daftarRole = [];
  List<Map<String, dynamic>> _daftarOutlet = [];

  bool get _modeEdit => widget.penggunaEdit != null;

  @override
  void initState() {
    super.initState();
    _roleId = widget.penggunaEdit?['role_id'] as String?;
    _outletIdsTerpilih = {
      ...((widget.penggunaEdit?['outlet_ids'] as List?)?.cast<String>() ?? const <String>[]),
    };
    _muatRoleDanOutlet();
  }

  @override
  void dispose() {
    _namaController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _muatRoleDanOutlet() async {
    try {
      final sesi = await ref.read(authSessionStoreProvider).muat();
      if (sesi == null) {
        setState(() => _error = 'Device belum pairing ke backend.');
        return;
      }
      final api = ref.read(backendApiProvider);
      final roles = await api.getJson(accessToken: sesi.accessToken, path: '/roles') as List;
      final outlets = await api.getJson(accessToken: sesi.accessToken, path: '/outlets') as List;
      _daftarRole = roles.cast<Map<String, dynamic>>();
      _daftarOutlet = outlets.cast<Map<String, dynamic>>();
    } catch (e) {
      _error = 'Gagal memuat role/outlet: $e';
    } finally {
      if (mounted) setState(() => _memuat = false);
    }
  }

  Future<void> _simpan() async {
    if (!_formKey.currentState!.validate()) return;
    if (_roleId == null) {
      setState(() => _error = 'Pilih role dulu');
      return;
    }
    final sesi = await ref.read(authSessionStoreProvider).muat();
    if (sesi == null) {
      setState(() => _error = 'Device belum pairing ke backend.');
      return;
    }
    setState(() {
      _menyimpan = true;
      _error = null;
    });
    try {
      final api = ref.read(backendApiProvider);
      final Map<String, dynamic> hasil;
      if (_modeEdit) {
        hasil = await api.patchJson(
              accessToken: sesi.accessToken,
              path: '/pengguna/${widget.penggunaEdit!['id']}',
              body: {
                'nama': _namaController.text.trim(),
                'role_id': _roleId,
                'aktif': _aktif,
                'outlet_ids': _outletIdsTerpilih.toList(),
              },
            ) as Map<String, dynamic>;
      } else {
        hasil = await api.postJson(
              accessToken: sesi.accessToken,
              path: '/pengguna',
              body: {
                'nama': _namaController.text.trim(),
                'role_id': _roleId,
                'pin': _pinController.text,
                'outlet_ids': _outletIdsTerpilih.toList(),
              },
            ) as Map<String, dynamic>;
      }

      await ref.read(_penggunaDaoProvider).upsertPenggunaDariSync(PenggunaCompanion.insert(
            id: hasil['id'] as String,
            tokoId: hasil['toko_id'] as String,
            roleId: hasil['role_id'] as String,
            nama: hasil['nama'] as String,
            noHp: Value(hasil['no_hp'] as String?),
            aktif: Value(hasil['aktif'] as bool),
            serverPenggunaId: Value(hasil['id'] as String),
            // Baru dibuat (bukan edit) - PIN-nya diketahui di sini,
            // langsung dihash lokal (sama algoritma dgn server) supaya
            // bisa login offline SEKARANG, tidak perlu nunggu sync pull.
            pinHash: _modeEdit ? const Value.absent() : Value(hashPin(_pinController.text)),
            createdAt: DateTime.now().millisecondsSinceEpoch,
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          ));

      if (mounted) context.pop();
    } catch (e) {
      setState(() => _error = 'Gagal menyimpan: $e');
    } finally {
      if (mounted) setState(() => _menyimpan = false);
    }
  }

  Future<void> _resetPin() async {
    final pinBaruController = TextEditingController();
    final pinBaru = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset PIN'),
        content: TextField(
          controller: pinBaruController,
          autofocus: true,
          obscureText: true,
          maxLength: 6,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'PIN baru (6 digit)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Batal')),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(pinBaruController.text),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (pinBaru == null || pinBaru.length != 6) return;
    final sesi = await ref.read(authSessionStoreProvider).muat();
    if (sesi == null) return;

    try {
      await ref.read(backendApiProvider).postJson(
            accessToken: sesi.accessToken,
            path: '/pengguna/${widget.penggunaEdit!['id']}/reset-pin',
            body: {'pin': pinBaru},
          );
      // PIN-nya diketahui di sini (user baru mengetiknya) - hash lokal
      // langsung diperbarui, konsisten dgn alasan di _simpan().
      await ref.read(_penggunaDaoProvider).updatePengguna(
            widget.penggunaEdit!['id'] as String,
            PenggunaCompanion(pinHash: Value(hashPin(pinBaru))),
          );
      if (mounted) {
        showAppToast(context, message: 'PIN berhasil direset', variant: ToastVariant.success);
      }
    } catch (e) {
      if (mounted) {
        showAppToast(context, message: 'Gagal reset PIN: $e', variant: ToastVariant.danger);
      }
    }
  }

  Future<void> _hapus() async {
    final konfirmasi = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus karyawan?'),
        content: Text('"${widget.penggunaEdit!['nama']}" tidak akan bisa login lagi.'),
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
            path: '/pengguna/${widget.penggunaEdit!['id']}',
          );
      await ref.read(_penggunaDaoProvider).updatePengguna(
            widget.penggunaEdit!['id'] as String,
            const PenggunaCompanion(aktif: Value(false)),
          );
      if (mounted) context.pop();
    } catch (e) {
      setState(() => _error = 'Gagal menghapus: $e');
    } finally {
      if (mounted) setState(() => _menghapus = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final online = isOnlineSaat(ref);
    return Scaffold(
      appBar: AppBar(
        title: Text(_modeEdit ? 'Ubah Pengguna' : 'Tambah Pengguna'),
        actions: [
          if (_modeEdit)
            IconButton(
              key: const Key('penggunaForm.hapus'),
              onPressed: _menghapus || !online ? null : _hapus,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: _memuat
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: SingleChildScrollView(
                key: const Key('penggunaForm.scrollView'),
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const OfflineNoticeBanner(),
                      if (_error != null) ...[
                        Text(_error!, style: const TextStyle(color: Colors.red)),
                        const SizedBox(height: AppSpacing.sm),
                      ],
                      TextFormField(
                        key: const Key('penggunaForm.nama'),
                        controller: _namaController,
                        decoration: const InputDecoration(labelText: 'Nama'),
                        validator: (value) =>
                            (value == null || value.trim().isEmpty) ? 'Nama wajib diisi' : null,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      DropdownButtonFormField<String>(
                        key: const Key('penggunaForm.role'),
                        initialValue: _roleId,
                        decoration: const InputDecoration(labelText: 'Role'),
                        items: _daftarRole
                            .map((r) => DropdownMenuItem(value: r['id'] as String, child: Text(r['nama'] as String)))
                            .toList(),
                        onChanged: (value) => setState(() => _roleId = value),
                        validator: (value) => value == null ? 'Pilih role' : null,
                      ),
                      if (!_modeEdit) ...[
                        const SizedBox(height: AppSpacing.lg),
                        TextFormField(
                          key: const Key('penggunaForm.pin'),
                          controller: _pinController,
                          decoration: const InputDecoration(labelText: 'PIN (6 digit)'),
                          keyboardType: TextInputType.number,
                          obscureText: true,
                          maxLength: 6,
                          validator: (value) {
                            if (value == null || value.length != 6 || int.tryParse(value) == null) {
                              return 'PIN harus 6 digit angka';
                            }
                            return null;
                          },
                        ),
                      ],
                      if (_modeEdit) ...[
                        const SizedBox(height: AppSpacing.lg),
                        Material(
                          type: MaterialType.transparency,
                          child: SwitchListTile(
                            key: const Key('penggunaForm.aktif'),
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Aktif'),
                            value: _aktif,
                            onChanged: (value) => setState(() => _aktif = value),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        OutlinedButton.icon(
                          key: const Key('penggunaForm.resetPin'),
                          onPressed: online ? _resetPin : null,
                          icon: const Icon(Icons.lock_reset_outlined),
                          label: const Text('Reset PIN'),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.lg),
                      Text('Akses outlet', style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: AppSpacing.sm),
                      for (final outlet in _daftarOutlet)
                        Material(
                          type: MaterialType.transparency,
                          child: CheckboxListTile(
                            key: Key('penggunaForm.outlet.${outlet['id']}'),
                            contentPadding: EdgeInsets.zero,
                            title: Text(outlet['nama'] as String),
                            value: _outletIdsTerpilih.contains(outlet['id']),
                            onChanged: (v) => setState(() {
                              if (v ?? false) {
                                _outletIdsTerpilih.add(outlet['id'] as String);
                              } else {
                                _outletIdsTerpilih.remove(outlet['id']);
                              }
                            }),
                          ),
                        ),
                      const SizedBox(height: AppSpacing.xxxl),
                      AppPrimaryButton(
                        key: const Key('penggunaForm.simpan'),
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
