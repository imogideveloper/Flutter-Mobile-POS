import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/network/auth_session_store.dart';
import '../../../../core/network/dio_backend_api.dart';
import '../../../../core/providers/session_provider.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/fitur_terkunci.dart';
import '../../../../core/widgets/offline_notice_banner.dart';
import '../../../../core/widgets/section_header.dart';
import '../../domain/pelanggan.dart';
import '../providers/pelanggan_providers.dart';

/// Tahap 5 C.9 - "level member dan aturan poin". Level member: list kecil
/// + dialog add/edit (pola sama dgn TipeOrderMejaPage). Aturan poin: SATU
/// baris per toko (toko_id = PK di backend) - form inline, bukan dialog,
/// disimpan lewat PUT /aturan-poin (upsert, sesuai komentar router
/// backend "satu toko cuma punya satu baris aturan_poin").
class LevelMemberAturanPoinPage extends ConsumerWidget {
  const LevelMemberAturanPoinPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final levelMember = ref.watch(levelMemberProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Level Member & Poin')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        children: [
          const OfflineNoticeBanner(),
          FiturTerkunci(
            kode: 'diskon_member',
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const SectionHeader(label: 'Level Member'),
                IconButton(
                  key: const Key('levelMemberPoin.tambahLevel'),
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () => showDialog(
                    context: context,
                    builder: (context) => const _LevelMemberDialog(),
                  ),
                ),
              ],
            ),
          ),
          levelMember.when(
            data: (daftar) => daftar.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                    child: EmptyState(icon: Icons.workspace_premium_outlined, message: 'Belum ada level member'),
                  )
                : Column(
                    children: [
                      for (final lm in daftar)
                        AppCard(
                          onTap: () => showDialog(
                            context: context,
                            builder: (context) => _LevelMemberDialog(levelMemberEdit: lm),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(lm.nama),
                                    Text(
                                      'Min belanja Rp${lm.minTotalBelanja} - diskon ${lm.diskonPersen}%',
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                              Text('${lm.pengaliPoin}x poin'),
                            ],
                          ),
                        ),
                    ],
                  ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, s) => Text('Gagal memuat: $e'),
          ),
          const SizedBox(height: AppSpacing.xl),
          const FiturTerkunci(
            kode: 'poin_loyalitas',
            child: SectionHeader(label: 'Aturan Poin'),
          ),
          const _AturanPoinForm(),
        ],
      ),
    );
  }
}

class _LevelMemberDialog extends ConsumerStatefulWidget {
  const _LevelMemberDialog({this.levelMemberEdit});

  final LevelMember? levelMemberEdit;

  @override
  ConsumerState<_LevelMemberDialog> createState() => _LevelMemberDialogState();
}

class _LevelMemberDialogState extends ConsumerState<_LevelMemberDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _namaController = TextEditingController(text: widget.levelMemberEdit?.nama ?? '');
  late final _minBelanjaController =
      TextEditingController(text: (widget.levelMemberEdit?.minTotalBelanja ?? 0).toString());
  late final _diskonController =
      TextEditingController(text: (widget.levelMemberEdit?.diskonPersen ?? 0).toString());
  late final _pengaliController =
      TextEditingController(text: (widget.levelMemberEdit?.pengaliPoin ?? 1).toString());
  bool _menyimpan = false;
  bool _menghapus = false;
  String? _error;

  bool get _modeEdit => widget.levelMemberEdit != null;

  @override
  void dispose() {
    _namaController.dispose();
    _minBelanjaController.dispose();
    _diskonController.dispose();
    _pengaliController.dispose();
    super.dispose();
  }

  Future<void> _simpan() async {
    if (!_formKey.currentState!.validate()) return;
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
      final body = {
        'nama': _namaController.text.trim(),
        'min_total_belanja': _minBelanjaController.text.trim().isEmpty ? '0' : _minBelanjaController.text.trim(),
        'diskon_persen': _diskonController.text.trim().isEmpty ? '0' : _diskonController.text.trim(),
        'pengali_poin': _pengaliController.text.trim().isEmpty ? '1' : _pengaliController.text.trim(),
      };
      final Map<String, dynamic> hasil;
      if (_modeEdit) {
        hasil = await ref.read(backendApiProvider).patchJson(
              accessToken: sesi.accessToken,
              path: '/level-member/${widget.levelMemberEdit!.id}',
              body: body,
            ) as Map<String, dynamic>;
      } else {
        hasil = await ref.read(backendApiProvider).postJson(
              accessToken: sesi.accessToken,
              path: '/level-member',
              body: body,
            ) as Map<String, dynamic>;
      }
      final tokoId = ref.read(currentTokoIdProvider);
      final now = DateTime.now().millisecondsSinceEpoch;
      await ref.read(pelangganDaoProvider).upsertLevelMember(LevelMemberCompanion.insert(
            id: hasil['id'] as String,
            tokoId: tokoId,
            nama: hasil['nama'] as String,
            minTotalBelanja: Value(double.parse(hasil['min_total_belanja'].toString()).round()),
            diskonPersen: Value(double.parse(hasil['diskon_persen'].toString())),
            pengaliPoin: Value(double.parse(hasil['pengali_poin'].toString())),
            urutan: Value(hasil['urutan'] as int),
            createdAt: now,
            updatedAt: now,
          ));
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = 'Gagal menyimpan: $e');
    } finally {
      if (mounted) setState(() => _menyimpan = false);
    }
  }

  Future<void> _hapus() async {
    final konfirmasi = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus level member?'),
        content: Text('"${widget.levelMemberEdit!.nama}" akan dihapus.'),
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
            path: '/level-member/${widget.levelMemberEdit!.id}',
          );
      await ref.read(pelangganDaoProvider).hapusLevelMemberLokal(widget.levelMemberEdit!.id);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = 'Gagal menghapus: $e');
    } finally {
      if (mounted) setState(() => _menghapus = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final online = isOnlineSaat(ref);
    return AlertDialog(
      title: Text(_modeEdit ? 'Ubah Level Member' : 'Tambah Level Member'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!online) const OfflineNoticeBanner(),
            if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
            TextFormField(
              key: const Key('levelMemberDialog.nama'),
              controller: _namaController,
              decoration: const InputDecoration(labelText: 'Nama level'),
              validator: (value) => (value == null || value.trim().isEmpty) ? 'Nama wajib diisi' : null,
            ),
            TextFormField(
              key: const Key('levelMemberDialog.minBelanja'),
              controller: _minBelanjaController,
              decoration: const InputDecoration(labelText: 'Minimal total belanja', prefixText: 'Rp '),
              keyboardType: TextInputType.number,
              validator: (value) => _validasiAngka(value),
            ),
            TextFormField(
              key: const Key('levelMemberDialog.diskon'),
              controller: _diskonController,
              decoration: const InputDecoration(labelText: 'Diskon (%)'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (value) => _validasiAngka(value),
            ),
            TextFormField(
              key: const Key('levelMemberDialog.pengali'),
              controller: _pengaliController,
              decoration: const InputDecoration(labelText: 'Pengali poin', helperText: 'Contoh: 1.5 = poin 1,5x'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (value) => _validasiAngka(value),
            ),
          ],
        ),
      ),
      actions: [
        if (_modeEdit)
          TextButton(
            key: const Key('levelMemberDialog.hapus'),
            onPressed: _menghapus || !online ? null : _hapus,
            child: const Text('Hapus'),
          ),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Batal')),
        FilledButton(
          key: const Key('levelMemberDialog.simpan'),
          onPressed: _menyimpan || !online ? null : _simpan,
          child: Text(_menyimpan ? 'Menyimpan...' : 'Simpan'),
        ),
      ],
    );
  }

  String? _validasiAngka(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    if (double.tryParse(value.trim()) == null) return 'Harus berupa angka';
    return null;
  }
}

class _AturanPoinForm extends ConsumerStatefulWidget {
  const _AturanPoinForm();

  @override
  ConsumerState<_AturanPoinForm> createState() => _AturanPoinFormState();
}

class _AturanPoinFormState extends ConsumerState<_AturanPoinForm> {
  final _formKey = GlobalKey<FormState>();
  final _nominalController = TextEditingController(text: '10000');
  final _nilaiTukarController = TextEditingController(text: '100');
  final _minTukarController = TextEditingController(text: '0');
  bool _aktif = true;
  bool _menyimpan = false;
  String? _error;
  bool _terisiDariServer = false;

  @override
  void dispose() {
    _nominalController.dispose();
    _nilaiTukarController.dispose();
    _minTukarController.dispose();
    super.dispose();
  }

  void _isiDariData(AturanPoin? data) {
    if (_terisiDariServer || data == null) return;
    _terisiDariServer = true;
    _nominalController.text = data.nominalPerPoin.toString();
    _nilaiTukarController.text = data.nilaiTukarPoin.toString();
    _minTukarController.text = data.minTukarPoin.toString();
    _aktif = data.aktif;
  }

  Future<void> _simpan() async {
    if (!_formKey.currentState!.validate()) return;
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
      final body = {
        'nominal_per_poin': _nominalController.text.trim(),
        'nilai_tukar_poin': _nilaiTukarController.text.trim(),
        'min_tukar_poin': int.tryParse(_minTukarController.text.trim()) ?? 0,
        'aktif': _aktif,
      };
      final hasil = await ref.read(backendApiProvider).putJsonBody(
            accessToken: sesi.accessToken,
            path: '/aturan-poin',
            body: body,
          ) as Map<String, dynamic>;
      final tokoId = ref.read(currentTokoIdProvider);
      final now = DateTime.now().millisecondsSinceEpoch;
      await ref.read(pelangganDaoProvider).upsertAturanPoin(AturanPoinCompanion.insert(
            tokoId: tokoId,
            nominalPerPoin: Value(double.parse(hasil['nominal_per_poin'].toString()).round()),
            nilaiTukarPoin: Value(double.parse(hasil['nilai_tukar_poin'].toString()).round()),
            minTukarPoin: Value(hasil['min_tukar_poin'] as int),
            kedaluwarsaHari: Value(hasil['kedaluwarsa_hari'] as int?),
            aktif: Value(hasil['aktif'] as bool),
            createdAt: now,
            updatedAt: now,
          ));
      if (mounted) {
        showAppToast(context, message: 'Aturan poin disimpan', variant: ToastVariant.success);
      }
    } catch (e) {
      setState(() => _error = 'Gagal menyimpan: $e');
    } finally {
      if (mounted) setState(() => _menyimpan = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final online = isOnlineSaat(ref);
    final aturanAsync = ref.watch(aturanPoinProvider);
    aturanAsync.whenData(_isiDariData);

    return AppCard(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_error != null) ...[
              Text(_error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: AppSpacing.sm),
            ],
            TextFormField(
              key: const Key('aturanPoinForm.nominalPerPoin'),
              controller: _nominalController,
              decoration: const InputDecoration(
                labelText: 'Nominal belanja per 1 poin',
                prefixText: 'Rp ',
              ),
              keyboardType: TextInputType.number,
              validator: (value) {
                if (value == null || value.trim().isEmpty) return 'Wajib diisi';
                if (int.tryParse(value.trim()) == null) return 'Harus berupa angka';
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              key: const Key('aturanPoinForm.nilaiTukarPoin'),
              controller: _nilaiTukarController,
              decoration: const InputDecoration(
                labelText: 'Nilai tukar per 1 poin',
                prefixText: 'Rp ',
                helperText: '1 poin bisa ditukar senilai berapa rupiah',
              ),
              keyboardType: TextInputType.number,
              validator: (value) {
                if (value == null || value.trim().isEmpty) return 'Wajib diisi';
                if (int.tryParse(value.trim()) == null) return 'Harus berupa angka';
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              key: const Key('aturanPoinForm.minTukarPoin'),
              controller: _minTukarController,
              decoration: const InputDecoration(labelText: 'Minimal poin utk ditukar'),
              keyboardType: TextInputType.number,
              validator: (value) {
                if (value == null || value.trim().isEmpty) return null;
                if (int.tryParse(value.trim()) == null) return 'Harus berupa angka';
                return null;
              },
            ),
            Material(
              type: MaterialType.transparency,
              child: SwitchListTile(
                key: const Key('aturanPoinForm.aktif'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Aktif'),
                value: _aktif,
                onChanged: (value) => setState(() => _aktif = value),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            AppPrimaryButton(
              key: const Key('aturanPoinForm.simpan'),
              label: _menyimpan ? 'Menyimpan...' : 'Simpan aturan poin',
              onPressed: _menyimpan || !online ? null : _simpan,
            ),
          ],
        ),
      ),
    );
  }
}
