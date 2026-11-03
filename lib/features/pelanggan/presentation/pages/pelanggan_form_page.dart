import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/network/auth_session_store.dart';
import '../../../../core/network/dio_backend_api.dart';
import '../../../../core/providers/session_provider.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/offline_notice_banner.dart';
import '../../domain/pelanggan.dart';
import '../providers/pelanggan_providers.dart';

/// Tahap 5 C.3 - "edit dan hapus, termasuk batas kasbon, level member".
/// Sama pola dgn PajakFormPage: SELALU online (Prinsip 1), tulis langsung
/// ke backend lalu cache lokal diperbarui.
class PelangganFormPage extends ConsumerStatefulWidget {
  const PelangganFormPage({super.key, this.pelangganEdit});

  final Pelanggan? pelangganEdit;

  @override
  ConsumerState<PelangganFormPage> createState() => _PelangganFormPageState();
}

class _PelangganFormPageState extends ConsumerState<PelangganFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final _namaController = TextEditingController(text: widget.pelangganEdit?.nama ?? '');
  late final _noHpController = TextEditingController(text: widget.pelangganEdit?.noHp ?? '');
  late final _emailController = TextEditingController(text: widget.pelangganEdit?.email ?? '');
  late final _catatanController = TextEditingController(text: widget.pelangganEdit?.catatan ?? '');
  late final _batasKasbonController =
      TextEditingController(text: widget.pelangganEdit?.batasKasbon?.toString() ?? '');
  late String? _levelMemberId = widget.pelangganEdit?.levelMemberId;
  bool _menyimpan = false;
  bool _menghapus = false;
  String? _errorServer;

  bool get _modeEdit => widget.pelangganEdit != null;

  @override
  void dispose() {
    _namaController.dispose();
    _noHpController.dispose();
    _emailController.dispose();
    _catatanController.dispose();
    _batasKasbonController.dispose();
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
        'no_hp': _noHpController.text.trim().isEmpty ? null : _noHpController.text.trim(),
        'email': _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
        'catatan': _catatanController.text.trim().isEmpty ? null : _catatanController.text.trim(),
        'batas_kasbon':
            _batasKasbonController.text.trim().isEmpty ? null : _batasKasbonController.text.trim(),
        'level_member_id': _levelMemberId,
      };
      final Map<String, dynamic> hasil;
      if (_modeEdit) {
        hasil = await ref.read(backendApiProvider).patchJson(
              accessToken: sesi.accessToken,
              path: '/pelanggan/${widget.pelangganEdit!.id}',
              body: body,
            ) as Map<String, dynamic>;
      } else {
        hasil = await ref.read(backendApiProvider).postJson(
              accessToken: sesi.accessToken,
              path: '/pelanggan',
              body: body,
            ) as Map<String, dynamic>;
      }

      final tokoId = ref.read(currentTokoIdProvider);
      final now = DateTime.now().millisecondsSinceEpoch;
      await ref.read(pelangganDaoProvider).upsertPelanggan(PelangganCompanion.insert(
            id: hasil['id'] as String,
            tokoId: tokoId,
            nama: hasil['nama'] as String,
            noHp: Value(hasil['no_hp'] as String?),
            email: Value(hasil['email'] as String?),
            levelMemberId: Value(hasil['level_member_id'] as String?),
            poin: Value((hasil['poin'] as int?) ?? 0),
            totalBelanja: Value(double.parse((hasil['total_belanja'] ?? 0).toString()).round()),
            batasKasbon: Value(
              hasil['batas_kasbon'] == null ? null : double.parse(hasil['batas_kasbon'].toString()).round(),
            ),
            catatan: Value(hasil['catatan'] as String?),
            createdAt: now,
            updatedAt: now,
          ));

      if (mounted) Navigator.of(context).pop();
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
        title: const Text('Hapus pelanggan?'),
        content: Text('"${widget.pelangganEdit!.nama}" akan dihapus. Transaksi lama tidak terpengaruh.'),
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
            path: '/pelanggan/${widget.pelangganEdit!.id}',
          );
      await ref.read(pelangganDaoProvider).hapusLokal(widget.pelangganEdit!.id);
      if (mounted) Navigator.of(context).pop();
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
    final levelMemberAsync = ref.watch(levelMemberProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(_modeEdit ? 'Ubah pelanggan' : 'Tambah pelanggan'),
        actions: [
          if (_modeEdit)
            IconButton(
              key: const Key('pelangganForm.hapus'),
              onPressed: _menghapus || !online ? null : _hapus,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          key: const Key('pelangganForm.scrollView'),
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const OfflineNoticeBanner(),
              if (_errorServer != null) ...[
                Text(_errorServer!, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: AppSpacing.sm),
              ],
              TextFormField(
                key: const Key('pelangganForm.nama'),
                controller: _namaController,
                decoration: const InputDecoration(labelText: 'Nama'),
                textCapitalization: TextCapitalization.words,
                validator: (value) =>
                    (value == null || value.trim().isEmpty) ? 'Nama wajib diisi' : null,
              ),
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                key: const Key('pelangganForm.noHp'),
                controller: _noHpController,
                decoration: const InputDecoration(labelText: 'No. HP'),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                key: const Key('pelangganForm.email'),
                controller: _emailController,
                decoration: const InputDecoration(labelText: 'Email (opsional)'),
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) return null;
                  if (!value.contains('@')) return 'Email tidak valid';
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                key: const Key('pelangganForm.batasKasbon'),
                controller: _batasKasbonController,
                decoration: const InputDecoration(
                  labelText: 'Batas kasbon (opsional)',
                  helperText: 'Kosongkan jika tidak ada batas',
                  prefixText: 'Rp ',
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) return null;
                  if (int.tryParse(value.trim()) == null) return 'Harus berupa angka';
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.lg),
              levelMemberAsync.when(
                data: (daftar) => DropdownButtonFormField<String?>(
                  key: const Key('pelangganForm.levelMember'),
                  initialValue: _levelMemberId,
                  decoration: const InputDecoration(labelText: 'Level member (opsional)'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Tanpa level')),
                    ...daftar.map((lm) => DropdownMenuItem(value: lm.id, child: Text(lm.nama))),
                  ],
                  onChanged: (value) => setState(() => _levelMemberId = value),
                ),
                loading: () => const SizedBox.shrink(),
                error: (error, stackTrace) => const SizedBox.shrink(),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                key: const Key('pelangganForm.catatan'),
                controller: _catatanController,
                decoration: const InputDecoration(labelText: 'Catatan (opsional)'),
                maxLines: 2,
              ),
              if (_modeEdit) ...[
                const SizedBox(height: AppSpacing.lg),
                OutlinedButton.icon(
                  key: const Key('pelangganForm.riwayatPoin'),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (context) => RiwayatPoinPage(
                      pelangganId: widget.pelangganEdit!.id,
                      namaPelanggan: widget.pelangganEdit!.nama,
                    ),
                  )),
                  icon: const Icon(Icons.history),
                  label: const Text('Riwayat poin'),
                ),
              ],
              const SizedBox(height: AppSpacing.xxl),
              AppPrimaryButton(
                key: const Key('pelangganForm.simpan'),
                label: _menyimpan ? 'Menyimpan...' : 'Simpan pelanggan',
                onPressed: _menyimpan || !online ? null : _simpan,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tahap 5 C.3 - riwayat poin SELALU diambil dari server (bukan drift
/// lokal) krn poin bisa didapat/dipakai dari HP lain - lihat
/// BackendApi.getJson di atas, path `/pelanggan/{id}/riwayat-poin`.
class RiwayatPoinPage extends ConsumerStatefulWidget {
  const RiwayatPoinPage({super.key, required this.pelangganId, required this.namaPelanggan});

  final String pelangganId;
  final String namaPelanggan;

  @override
  ConsumerState<RiwayatPoinPage> createState() => _RiwayatPoinPageState();
}

class _RiwayatPoinPageState extends ConsumerState<RiwayatPoinPage> {
  bool _memuat = true;
  String? _error;
  List<Map<String, dynamic>> _riwayat = [];

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
        setState(() => _error = 'Device belum pairing ke backend.');
        return;
      }
      final hasil = await ref.read(backendApiProvider).getJson(
            accessToken: sesi.accessToken,
            path: '/pelanggan/${widget.pelangganId}/riwayat-poin',
          );
      _riwayat = (hasil as List).cast<Map<String, dynamic>>();
    } catch (e) {
      _error = 'Gagal memuat riwayat: $e';
    } finally {
      if (mounted) setState(() => _memuat = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Riwayat poin - ${widget.namaPelanggan}')),
      body: _memuat
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _riwayat.isEmpty
                  ? const Center(child: Text('Belum ada riwayat poin.'))
                  : ListView.separated(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      itemCount: _riwayat.length,
                      separatorBuilder: (context, index) => const Divider(),
                      itemBuilder: (context, index) {
                        final item = _riwayat[index];
                        final poin = item['poin'] as int;
                        return ListTile(
                          leading: Icon(poin >= 0 ? Icons.add_circle_outline : Icons.remove_circle_outline),
                          title: Text('${poin >= 0 ? '+' : ''}$poin poin'),
                          subtitle: Text(item['keterangan'] as String? ?? '-'),
                          trailing: Text((item['created_at'] as String).substring(0, 10)),
                        );
                      },
                    ),
    );
  }
}
