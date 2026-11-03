import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/network/auth_session_store.dart';
import '../../../../core/network/dio_backend_api.dart';
import '../../../../core/providers/session_provider.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/fitur_terkunci.dart';
import '../../../../core/widgets/offline_notice_banner.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../dapur/domain/meja.dart';
import '../../../dapur/presentation/providers/meja_providers.dart';
import '../../../promo/data/local/tables/pajak_table.dart' show PajakTipe;
import '../../../promo/presentation/providers/pajak_providers.dart';
import '../../data/local/tables/tipe_order_table.dart' hide TipeOrder;
import '../../domain/tipe_order.dart';
import '../providers/tipe_order_providers.dart';

const _labelKanal = {
  TipeOrderKanal.makanDiTempat: 'Makan di tempat',
  TipeOrderKanal.bawaPulang: 'Bawa pulang',
  TipeOrderKanal.antar: 'Antar',
  TipeOrderKanal.online: 'Online',
  TipeOrderKanal.langsung: 'Langsung',
};

/// Tahap 5 C.7 - "tipe pesanan dan meja: kelola keduanya". Dua entitas
/// kecil & sejenis digabung di 1 layar (dialog add/edit, bukan halaman
/// penuh) - pola sama dgn PengaturanMetodeBayarPage._editNamaUrutan.
class TipeOrderMejaPage extends ConsumerWidget {
  const TipeOrderMejaPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tipeOrderAktif = ref.watch(tipeOrderAktifProvider);
    final mejaAktif = ref.watch(mejaAktifProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Tipe Pesanan & Meja')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        children: [
          const OfflineNoticeBanner(),
          FiturTerkunci(
            kode: 'tipe_order',
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const SectionHeader(label: 'Tipe Pesanan'),
                IconButton(
                  key: const Key('tipeOrderMeja.tambahTipeOrder'),
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () => _bukaDialogTipeOrder(context, ref),
                ),
              ],
            ),
          ),
          tipeOrderAktif.when(
            data: (daftar) => daftar.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                    child: EmptyState(icon: Icons.list_alt_outlined, message: 'Belum ada tipe pesanan'),
                  )
                : Column(
                    children: [
                      for (final t in daftar)
                        AppCard(
                          onTap: () => _bukaDialogTipeOrder(context, ref, tipeOrderEdit: t),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(t.nama),
                                    Text(_labelKanal[t.kanal] ?? t.kanal.name,
                                        style: Theme.of(context).textTheme.bodySmall),
                                  ],
                                ),
                              ),
                              if (t.pakaiMeja) const Icon(Icons.table_restaurant_outlined, size: 18),
                            ],
                          ),
                        ),
                    ],
                  ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, s) => Text('Gagal memuat: $e'),
          ),
          const SizedBox(height: AppSpacing.xl),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SectionHeader(label: 'Meja'),
              IconButton(
                key: const Key('tipeOrderMeja.tambahMeja'),
                icon: const Icon(Icons.add_circle_outline),
                onPressed: () => _bukaDialogMeja(context, ref),
              ),
            ],
          ),
          mejaAktif.when(
            data: (daftar) => daftar.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                    child: EmptyState(icon: Icons.table_restaurant_outlined, message: 'Belum ada meja'),
                  )
                : Column(
                    children: [
                      for (final m in daftar)
                        AppCard(
                          onTap: () => _bukaDialogMeja(context, ref, mejaEdit: m),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(m.nama),
                                    if (m.area != null)
                                      Text(m.area!, style: Theme.of(context).textTheme.bodySmall),
                                  ],
                                ),
                              ),
                              if (m.kapasitas != null) Text('${m.kapasitas} kursi'),
                            ],
                          ),
                        ),
                    ],
                  ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, s) => Text('Gagal memuat: $e'),
          ),
        ],
      ),
    );
  }

  Future<void> _bukaDialogTipeOrder(BuildContext context, WidgetRef ref, {TipeOrder? tipeOrderEdit}) {
    return showDialog(
      context: context,
      builder: (context) => _TipeOrderDialog(tipeOrderEdit: tipeOrderEdit),
    );
  }

  Future<void> _bukaDialogMeja(BuildContext context, WidgetRef ref, {Meja? mejaEdit}) {
    return showDialog(
      context: context,
      builder: (context) => _MejaDialog(mejaEdit: mejaEdit),
    );
  }
}

class _TipeOrderDialog extends ConsumerStatefulWidget {
  const _TipeOrderDialog({this.tipeOrderEdit});

  final TipeOrder? tipeOrderEdit;

  @override
  ConsumerState<_TipeOrderDialog> createState() => _TipeOrderDialogState();
}

class _TipeOrderDialogState extends ConsumerState<_TipeOrderDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _namaController = TextEditingController(text: widget.tipeOrderEdit?.nama ?? '');
  late TipeOrderKanal _kanal = widget.tipeOrderEdit?.kanal ?? TipeOrderKanal.langsung;
  late bool _pakaiMeja = widget.tipeOrderEdit?.pakaiMeja ?? false;
  bool _menyimpan = false;
  bool _menghapus = false;
  String? _error;
  bool _memuatServicePajak = true;
  Set<String> _servicePajakTerpilih = {};

  bool get _modeEdit => widget.tipeOrderEdit != null;

  @override
  void initState() {
    super.initState();
    if (_modeEdit) _muatServicePajak();
  }

  @override
  void dispose() {
    _namaController.dispose();
    super.dispose();
  }

  Future<void> _muatServicePajak() async {
    try {
      final sesi = await ref.read(authSessionStoreProvider).muat();
      if (sesi == null) return;
      final hasil = await ref.read(backendApiProvider).getJson(
            accessToken: sesi.accessToken,
            path: '/tipe-order/${widget.tipeOrderEdit!.id}/pajak',
          );
      _servicePajakTerpilih = (hasil as List).map((e) => e['pajak_id'] as String).toSet();
    } catch (_) {
      // Diam-diam - daftar service bukan blocker simpan nama/kanal.
    } finally {
      if (mounted) setState(() => _memuatServicePajak = false);
    }
  }

  Future<void> _toggleServicePajak(String pajakId, bool aktif) async {
    final sesi = await ref.read(authSessionStoreProvider).muat();
    if (sesi == null) return;
    try {
      if (aktif) {
        await ref.read(backendApiProvider).postJson(
              accessToken: sesi.accessToken,
              path: '/tipe-order/${widget.tipeOrderEdit!.id}/pajak/$pajakId',
            );
      } else {
        await ref.read(backendApiProvider).deleteJson(
              accessToken: sesi.accessToken,
              path: '/tipe-order/${widget.tipeOrderEdit!.id}/pajak/$pajakId',
            );
      }
      setState(() {
        if (aktif) {
          _servicePajakTerpilih.add(pajakId);
        } else {
          _servicePajakTerpilih.remove(pajakId);
        }
      });
    } catch (e) {
      if (mounted) {
        showAppToast(context, message: 'Gagal mengubah: $e', variant: ToastVariant.danger);
      }
    }
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
        'kanal': tipeOrderKanalPostgresValue[_kanal],
        'pakai_meja': _pakaiMeja,
      };
      final Map<String, dynamic> hasil;
      if (_modeEdit) {
        hasil = await ref.read(backendApiProvider).patchJson(
              accessToken: sesi.accessToken,
              path: '/tipe-order/${widget.tipeOrderEdit!.id}',
              body: body,
            ) as Map<String, dynamic>;
      } else {
        hasil = await ref.read(backendApiProvider).postJson(
              accessToken: sesi.accessToken,
              path: '/tipe-order',
              body: body,
            ) as Map<String, dynamic>;
      }
      final tokoId = ref.read(currentTokoIdProvider);
      final now = DateTime.now().millisecondsSinceEpoch;
      final kanalBalik = tipeOrderKanalPostgresValue.entries
          .firstWhere((e) => e.value == hasil['kanal'], orElse: () => const MapEntry(TipeOrderKanal.langsung, ''))
          .key;
      await ref.read(tipeOrderDaoProvider).upsertTipeOrder(TipeOrderCompanion.insert(
            id: hasil['id'] as String,
            tokoId: tokoId,
            nama: hasil['nama'] as String,
            kanal: kanalBalik,
            pakaiMeja: Value(hasil['pakai_meja'] as bool),
            markupPersen: Value(double.parse(hasil['markup_persen'].toString())),
            urutan: Value(hasil['urutan'] as int),
            aktif: Value(hasil['aktif'] as bool),
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
        title: const Text('Hapus tipe pesanan?'),
        content: Text('"${widget.tipeOrderEdit!.nama}" akan dinonaktifkan.'),
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
            path: '/tipe-order/${widget.tipeOrderEdit!.id}',
          );
      await ref.read(tipeOrderDaoProvider).nonaktifkanLokal(widget.tipeOrderEdit!.id);
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
      title: Text(_modeEdit ? 'Ubah Tipe Pesanan' : 'Tambah Tipe Pesanan'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!online) const OfflineNoticeBanner(),
            if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
            TextFormField(
              key: const Key('tipeOrderDialog.nama'),
              controller: _namaController,
              decoration: const InputDecoration(labelText: 'Nama'),
              validator: (value) => (value == null || value.trim().isEmpty) ? 'Nama wajib diisi' : null,
            ),
            DropdownButtonFormField<TipeOrderKanal>(
              key: const Key('tipeOrderDialog.kanal'),
              initialValue: _kanal,
              decoration: const InputDecoration(labelText: 'Kanal'),
              items: TipeOrderKanal.values
                  .map((k) => DropdownMenuItem(value: k, child: Text(_labelKanal[k]!)))
                  .toList(),
              onChanged: (value) => setState(() => _kanal = value ?? _kanal),
            ),
            Material(
              type: MaterialType.transparency,
              child: SwitchListTile(
                key: const Key('tipeOrderDialog.pakaiMeja'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Pakai meja'),
                value: _pakaiMeja,
                onChanged: (value) => setState(() => _pakaiMeja = value),
              ),
            ),
            if (_modeEdit)
              FiturTerkunci(
                kode: 'service_per_tipe_order',
                child: Consumer(
                  builder: (context, ref, _) {
                    final tokoId = ref.watch(currentTokoIdProvider);
                    final pajakAsync = ref.watch(pajakAktifProvider(tokoId));
                    final daftarService =
                        pajakAsync.value?.where((p) => p.tipe == PajakTipe.service).toList() ?? [];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: AppSpacing.sm),
                        const SectionHeader(label: 'Service charge utk tipe ini'),
                        if (_memuatServicePajak)
                          const LinearProgressIndicator()
                        else if (daftarService.isEmpty)
                          const Text('Belum ada service charge di toko ini')
                        else
                          for (final pajak in daftarService)
                            Material(
                              type: MaterialType.transparency,
                              child: CheckboxListTile(
                                key: Key('tipeOrderDialog.service.${pajak.id}'),
                                contentPadding: EdgeInsets.zero,
                                title: Text(pajak.nama),
                                value: _servicePajakTerpilih.contains(pajak.id),
                                onChanged: (v) => _toggleServicePajak(pajak.id, v ?? false),
                              ),
                            ),
                      ],
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      actions: [
        if (_modeEdit)
          TextButton(
            key: const Key('tipeOrderDialog.hapus'),
            onPressed: _menghapus || !online ? null : _hapus,
            child: const Text('Hapus'),
          ),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Batal')),
        FilledButton(
          key: const Key('tipeOrderDialog.simpan'),
          onPressed: _menyimpan || !online ? null : _simpan,
          child: Text(_menyimpan ? 'Menyimpan...' : 'Simpan'),
        ),
      ],
    );
  }
}

class _MejaDialog extends ConsumerStatefulWidget {
  const _MejaDialog({this.mejaEdit});

  final Meja? mejaEdit;

  @override
  ConsumerState<_MejaDialog> createState() => _MejaDialogState();
}

class _MejaDialogState extends ConsumerState<_MejaDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _namaController = TextEditingController(text: widget.mejaEdit?.nama ?? '');
  late final _areaController = TextEditingController(text: widget.mejaEdit?.area ?? '');
  late final _kapasitasController =
      TextEditingController(text: widget.mejaEdit?.kapasitas?.toString() ?? '');
  bool _menyimpan = false;
  bool _menghapus = false;
  String? _error;

  bool get _modeEdit => widget.mejaEdit != null;

  @override
  void dispose() {
    _namaController.dispose();
    _areaController.dispose();
    _kapasitasController.dispose();
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
      final outletId = ref.read(currentOutletIdProvider);
      final body = {
        'nama': _namaController.text.trim(),
        'area': _areaController.text.trim().isEmpty ? null : _areaController.text.trim(),
        'kapasitas':
            _kapasitasController.text.trim().isEmpty ? null : int.parse(_kapasitasController.text.trim()),
      };
      final Map<String, dynamic> hasil;
      if (_modeEdit) {
        hasil = await ref.read(backendApiProvider).patchJson(
              accessToken: sesi.accessToken,
              path: '/outlets/$outletId/meja/${widget.mejaEdit!.id}',
              body: body,
            ) as Map<String, dynamic>;
      } else {
        hasil = await ref.read(backendApiProvider).postJson(
              accessToken: sesi.accessToken,
              path: '/outlets/$outletId/meja',
              body: body,
            ) as Map<String, dynamic>;
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      await ref.read(mejaDaoProvider).upsertMeja(MejaCompanion.insert(
            id: hasil['id'] as String,
            outletId: outletId,
            nama: hasil['nama'] as String,
            area: Value(hasil['area'] as String?),
            kapasitas: Value(hasil['kapasitas'] as int?),
            urutan: Value(hasil['urutan'] as int),
            aktif: Value(hasil['aktif'] as bool),
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
        title: const Text('Hapus meja?'),
        content: Text('"${widget.mejaEdit!.nama}" akan dinonaktifkan.'),
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
      final outletId = ref.read(currentOutletIdProvider);
      await ref.read(backendApiProvider).deleteJson(
            accessToken: sesi.accessToken,
            path: '/outlets/$outletId/meja/${widget.mejaEdit!.id}',
          );
      await ref.read(mejaDaoProvider).nonaktifkanLokal(widget.mejaEdit!.id);
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
      title: Text(_modeEdit ? 'Ubah Meja' : 'Tambah Meja'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!online) const OfflineNoticeBanner(),
            if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
            TextFormField(
              key: const Key('mejaDialog.nama'),
              controller: _namaController,
              decoration: const InputDecoration(labelText: 'Nama meja'),
              validator: (value) => (value == null || value.trim().isEmpty) ? 'Nama wajib diisi' : null,
            ),
            TextFormField(
              key: const Key('mejaDialog.area'),
              controller: _areaController,
              decoration: const InputDecoration(labelText: 'Area (opsional)'),
            ),
            TextFormField(
              key: const Key('mejaDialog.kapasitas'),
              controller: _kapasitasController,
              decoration: const InputDecoration(labelText: 'Kapasitas (opsional)'),
              keyboardType: TextInputType.number,
              validator: (value) {
                if (value == null || value.trim().isEmpty) return null;
                if (int.tryParse(value.trim()) == null) return 'Harus berupa angka';
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        if (_modeEdit)
          TextButton(
            key: const Key('mejaDialog.hapus'),
            onPressed: _menghapus || !online ? null : _hapus,
            child: const Text('Hapus'),
          ),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Batal')),
        FilledButton(
          key: const Key('mejaDialog.simpan'),
          onPressed: _menyimpan || !online ? null : _simpan,
          child: Text(_menyimpan ? 'Menyimpan...' : 'Simpan'),
        ),
      ],
    );
  }
}
