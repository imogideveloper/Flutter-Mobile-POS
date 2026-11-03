import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/network/auth_session_store.dart';
import '../../../../core/network/dio_backend_api.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/fitur_terkunci.dart';
import '../../../../core/widgets/offline_notice_banner.dart';
import '../../../../core/providers/session_provider.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../fitur/presentation/providers/feature_gate_provider.dart';
import '../../../promo/presentation/providers/pajak_providers.dart';
import '../../../transaksi/presentation/providers/harga_keranjang_provider.dart';
import '../providers/produk_providers.dart';

/// Dipakai seksi Resep/Bundling/Pajak-per-produk (lihat masing2 `_muat()`)
/// - [FiturTerkunci] di atasnya SUDAH meredupkan+mengunci tampilan child
/// kalau fitur belum terbuka, tapi child tetap ter-mount & SEBELUMNYA
/// tetap memanggil API sungguhan di baliknya (sia-sia, dan 403
/// `fitur_terkunci` yang terlempar bikin pesan error teknis muncul di
/// section yang sudah redup - bug nyata dari laporan pengguna). Skip
/// panggilan API kalau cache lokal SUDAH TAHU fitur ini terkunci; kalau
/// belum tahu (belum pernah sync - gate error/loading), tetap coba spt
/// biasa, server yang jadi penentu akhir.
bool _fiturTerkunciLokal(WidgetRef ref, String kode) {
  final gateAsync = ref.read(featureGateProvider);
  final gate = gateAsync is AsyncData<FeatureGate> ? gateAsync.value : null;
  return gate != null && !gate.has(kode);
}

/// Tahap 5 C.8 - "tab" (Resep/Bundling/Harga grosir/Harga per outlet) di
/// form produk, SENGAJA berupa seksi bertumpuk (bukan TabBarView
/// sungguhan - TabBarView butuh tinggi tetap, canggung di dalam
/// SingleChildScrollView form produk yang sudah ada) - cuma tampil di
/// mode edit, krn semua ini endpoint `/produk/{id}/...` yang butuh id
/// produk SUNGGUHAN (produk baru belum punya id sampai disimpan sekali).
/// Seksi "Pajak per produk" (C.6 - "atur pajak per produk") ikut di sini
/// krn sama-sama sub-resource produk.
class ProdukLanjutanSections extends StatelessWidget {
  const ProdukLanjutanSections({super.key, required this.produkId});

  final String produkId;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const OfflineNoticeBanner(),
        FiturTerkunci(kode: 'resep', child: _ResepSection(produkId: produkId)),
        const SizedBox(height: 16),
        FiturTerkunci(kode: 'bundling', child: _BundlingSection(produkId: produkId)),
        const SizedBox(height: 16),
        FiturTerkunci(kode: 'harga_grosir', child: _HargaGrosirSection(produkId: produkId)),
        const SizedBox(height: 16),
        _HargaOutletSection(produkId: produkId),
        const SizedBox(height: 16),
        FiturTerkunci(kode: 'pajak_per_produk', child: _ProdukPajakSection(produkId: produkId)),
      ],
    );
  }
}

class _ProdukPajakSection extends ConsumerStatefulWidget {
  const _ProdukPajakSection({required this.produkId});

  final String produkId;

  @override
  ConsumerState<_ProdukPajakSection> createState() => _ProdukPajakSectionState();
}

class _ProdukPajakSectionState extends ConsumerState<_ProdukPajakSection> {
  bool _memuat = true;
  String? _error;
  Set<String> _pajakTerpilih = {};

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    if (_fiturTerkunciLokal(ref, 'pajak_per_produk')) {
      setState(() => _memuat = false);
      return;
    }
    setState(() => _memuat = true);
    try {
      final sesi = await _ambilSesi(ref);
      if (sesi == null) return;
      final hasil = await ref.read(backendApiProvider).getJson(
            accessToken: sesi.accessToken,
            path: '/produk/${widget.produkId}/pajak',
          );
      _pajakTerpilih = (hasil as List).map((e) => e['pajak_id'] as String).toSet();
    } catch (e) {
      _error = 'Gagal memuat pajak produk: $e';
    } finally {
      if (mounted) setState(() => _memuat = false);
    }
  }

  Future<void> _toggle(String pajakId, bool aktif) async {
    final sesi = await _ambilSesi(ref);
    if (sesi == null) return;
    try {
      if (aktif) {
        await ref.read(backendApiProvider).postJson(
              accessToken: sesi.accessToken,
              path: '/produk/${widget.produkId}/pajak/$pajakId',
            );
      } else {
        await ref.read(backendApiProvider).deleteJson(
              accessToken: sesi.accessToken,
              path: '/produk/${widget.produkId}/pajak/$pajakId',
            );
      }
      setState(() {
        if (aktif) {
          _pajakTerpilih.add(pajakId);
        } else {
          _pajakTerpilih.remove(pajakId);
        }
      });
    } catch (e) {
      if (mounted) {
        showAppToast(context, message: 'Gagal mengubah: $e', variant: ToastVariant.danger);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final online = isOnlineSaat(ref);
    final tokoId = ref.watch(currentTokoIdProvider);
    final pajakAsync = ref.watch(pajakAktifProvider(tokoId));

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(label: 'Pajak khusus produk ini'),
          if (_memuat)
            const Center(child: CircularProgressIndicator())
          else if (_error != null)
            Text(_error!, style: const TextStyle(color: Colors.red))
          else
            pajakAsync.when(
              data: (daftarPajak) => daftarPajak.isEmpty
                  ? const EmptyState(icon: Icons.percent_outlined, message: 'Belum ada pajak/service toko')
                  : Column(
                      children: [
                        for (final pajak in daftarPajak)
                          Material(
                            type: MaterialType.transparency,
                            child: CheckboxListTile(
                              key: Key('produkPajak.${pajak.id}'),
                              contentPadding: EdgeInsets.zero,
                              title: Text(pajak.nama),
                              value: _pajakTerpilih.contains(pajak.id),
                              onChanged: online ? (v) => _toggle(pajak.id, v ?? false) : null,
                            ),
                          ),
                      ],
                    ),
              loading: () => const LinearProgressIndicator(),
              error: (e, s) => Text('Gagal memuat pajak: $e'),
            ),
        ],
      ),
    );
  }
}

/// Util bersama - semua seksi di file ini butuh sesi backend sebelum
/// memanggil endpoint apa pun.
Future<SesiBackend?> _ambilSesi(WidgetRef ref) => ref.read(authSessionStoreProvider).muat();

class _ResepSection extends ConsumerStatefulWidget {
  const _ResepSection({required this.produkId});

  final String produkId;

  @override
  ConsumerState<_ResepSection> createState() => _ResepSectionState();
}

class _ResepSectionState extends ConsumerState<_ResepSection> {
  bool _memuat = true;
  String? _error;
  List<Map<String, dynamic>> _daftar = [];

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    if (_fiturTerkunciLokal(ref, 'resep')) {
      setState(() => _memuat = false);
      return;
    }
    setState(() => _memuat = true);
    try {
      final sesi = await _ambilSesi(ref);
      if (sesi == null) return;
      final hasil = await ref.read(backendApiProvider).getJson(
            accessToken: sesi.accessToken,
            path: '/produk/${widget.produkId}/resep',
          );
      _daftar = (hasil as List).cast<Map<String, dynamic>>();
    } catch (e) {
      _error = 'Gagal memuat resep: $e';
    } finally {
      if (mounted) setState(() => _memuat = false);
    }
  }

  Future<void> _bukaDialog({Map<String, dynamic>? itemEdit}) async {
    final berubah = await showDialog<bool>(
      context: context,
      builder: (context) => _ResepBundlingDialog(
        produkId: widget.produkId,
        pathDasar: '/produk/${widget.produkId}/resep',
        labelPicker: 'Bahan baku',
        idField: 'bahan_id',
        itemEdit: itemEdit,
        idEdit: itemEdit?['id'] as String?,
        namaEdit: itemEdit?['nama_bahan'] as String?,
        qtyEdit: itemEdit?['qty'] as String?,
      ),
    );
    if (berubah == true) _muat();
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SectionHeader(label: 'Resep (bahan baku)'),
              IconButton(
                key: const Key('produkLanjutan.tambahResep'),
                icon: const Icon(Icons.add_circle_outline),
                onPressed: () => _bukaDialog(),
              ),
            ],
          ),
          if (_memuat)
            const Center(child: CircularProgressIndicator())
          else if (_error != null)
            Text(_error!, style: const TextStyle(color: Colors.red))
          else if (_daftar.isEmpty)
            const EmptyState(icon: Icons.soup_kitchen_outlined, message: 'Belum ada resep')
          else
            for (final item in _daftar)
              Material(
                type: MaterialType.transparency,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(item['nama_bahan'] as String),
                  trailing: Text('${item['qty']}'),
                  onTap: () => _bukaDialog(itemEdit: item),
                ),
              ),
        ],
      ),
    );
  }
}

class _BundlingSection extends ConsumerStatefulWidget {
  const _BundlingSection({required this.produkId});

  final String produkId;

  @override
  ConsumerState<_BundlingSection> createState() => _BundlingSectionState();
}

class _BundlingSectionState extends ConsumerState<_BundlingSection> {
  bool _memuat = true;
  String? _error;
  List<Map<String, dynamic>> _daftar = [];

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    if (_fiturTerkunciLokal(ref, 'bundling')) {
      setState(() => _memuat = false);
      return;
    }
    setState(() => _memuat = true);
    try {
      final sesi = await _ambilSesi(ref);
      if (sesi == null) return;
      final hasil = await ref.read(backendApiProvider).getJson(
            accessToken: sesi.accessToken,
            path: '/produk/${widget.produkId}/bundling',
          );
      _daftar = (hasil as List).cast<Map<String, dynamic>>();
    } catch (e) {
      _error = 'Gagal memuat bundling: $e';
    } finally {
      if (mounted) setState(() => _memuat = false);
    }
  }

  Future<void> _bukaDialog({Map<String, dynamic>? itemEdit}) async {
    final berubah = await showDialog<bool>(
      context: context,
      builder: (context) => _ResepBundlingDialog(
        produkId: widget.produkId,
        pathDasar: '/produk/${widget.produkId}/bundling',
        labelPicker: 'Produk isi bundling',
        idField: 'produk_id',
        itemEdit: itemEdit,
        idEdit: itemEdit?['id'] as String?,
        namaEdit: itemEdit?['nama_produk'] as String?,
        qtyEdit: itemEdit?['qty'] as String?,
      ),
    );
    if (berubah == true) _muat();
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SectionHeader(label: 'Bundling (isi paket)'),
              IconButton(
                key: const Key('produkLanjutan.tambahBundling'),
                icon: const Icon(Icons.add_circle_outline),
                onPressed: () => _bukaDialog(),
              ),
            ],
          ),
          if (_memuat)
            const Center(child: CircularProgressIndicator())
          else if (_error != null)
            Text(_error!, style: const TextStyle(color: Colors.red))
          else if (_daftar.isEmpty)
            const EmptyState(icon: Icons.inventory_2_outlined, message: 'Belum ada isi bundling')
          else
            for (final item in _daftar)
              Material(
                type: MaterialType.transparency,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(item['nama_produk'] as String),
                  trailing: Text('${item['qty']}'),
                  onTap: () => _bukaDialog(itemEdit: item),
                ),
              ),
        ],
      ),
    );
  }
}

/// Dialog add/edit bersama utk Resep & Bundling - keduanya sama bentuk
/// (pilih 1 produk + qty), cuma beda path & nama field id (`bahan_id` vs
/// `produk_id`).
class _ResepBundlingDialog extends ConsumerStatefulWidget {
  const _ResepBundlingDialog({
    required this.produkId,
    required this.pathDasar,
    required this.labelPicker,
    required this.idField,
    this.itemEdit,
    this.idEdit,
    this.namaEdit,
    this.qtyEdit,
  });

  final String produkId;
  final String pathDasar;
  final String labelPicker;
  final String idField;
  final Map<String, dynamic>? itemEdit;
  final String? idEdit;
  final String? namaEdit;
  final String? qtyEdit;

  @override
  ConsumerState<_ResepBundlingDialog> createState() => _ResepBundlingDialogState();
}

class _ResepBundlingDialogState extends ConsumerState<_ResepBundlingDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _qtyController = TextEditingController(text: widget.qtyEdit ?? '');
  String? _produkTerpilih;
  bool _menyimpan = false;
  bool _menghapus = false;
  String? _error;

  bool get _modeEdit => widget.itemEdit != null;

  @override
  void dispose() {
    _qtyController.dispose();
    super.dispose();
  }

  Future<void> _simpan() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_modeEdit && _produkTerpilih == null) {
      setState(() => _error = 'Pilih ${widget.labelPicker.toLowerCase()} dulu');
      return;
    }
    final sesi = await _ambilSesi(ref);
    if (sesi == null) {
      setState(() => _error = 'Device belum pairing ke backend.');
      return;
    }
    setState(() {
      _menyimpan = true;
      _error = null;
    });
    try {
      if (_modeEdit) {
        await ref.read(backendApiProvider).patchJson(
              accessToken: sesi.accessToken,
              path: '${widget.pathDasar}/${widget.idEdit}',
              body: {'qty': _qtyController.text.trim()},
            );
      } else {
        await ref.read(backendApiProvider).postJson(
              accessToken: sesi.accessToken,
              path: widget.pathDasar,
              body: {widget.idField: _produkTerpilih, 'qty': _qtyController.text.trim()},
            );
      }
      if (mounted) Navigator.of(context).pop(true);
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
        title: Text('Hapus ${widget.labelPicker.toLowerCase()}?'),
        content: Text(widget.namaEdit ?? ''),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Hapus')),
        ],
      ),
    );
    if (konfirmasi != true) return;
    final sesi = await _ambilSesi(ref);
    if (sesi == null) return;
    setState(() => _menghapus = true);
    try {
      await ref.read(backendApiProvider).deleteJson(
            accessToken: sesi.accessToken,
            path: '${widget.pathDasar}/${widget.idEdit}',
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _error = 'Gagal menghapus: $e');
    } finally {
      if (mounted) setState(() => _menghapus = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final online = isOnlineSaat(ref);
    final produkAsync = ref.watch(produkAktifProvider);

    return AlertDialog(
      title: Text(_modeEdit ? 'Ubah ${widget.labelPicker}' : 'Tambah ${widget.labelPicker}'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!online) const OfflineNoticeBanner(),
            if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
            if (_modeEdit)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(widget.namaEdit ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
              )
            else
              produkAsync.when(
                data: (daftar) => DropdownButtonFormField<String>(
                  key: const Key('resepBundlingDialog.produk'),
                  decoration: InputDecoration(labelText: widget.labelPicker),
                  items: daftar
                      .where((p) => p.id != widget.produkId)
                      .map((p) => DropdownMenuItem(value: p.id, child: Text(p.nama)))
                      .toList(),
                  onChanged: (value) => setState(() => _produkTerpilih = value),
                ),
                loading: () => const LinearProgressIndicator(),
                error: (e, s) => Text('Gagal memuat produk: $e'),
              ),
            TextFormField(
              key: const Key('resepBundlingDialog.qty'),
              controller: _qtyController,
              decoration: const InputDecoration(labelText: 'Qty'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (value) {
                if (value == null || value.trim().isEmpty) return 'Qty wajib diisi';
                if (double.tryParse(value) == null) return 'Harus berupa angka';
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        if (_modeEdit)
          TextButton(
            key: const Key('resepBundlingDialog.hapus'),
            onPressed: _menghapus || !online ? null : _hapus,
            child: const Text('Hapus'),
          ),
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Batal')),
        FilledButton(
          key: const Key('resepBundlingDialog.simpan'),
          onPressed: _menyimpan || !online ? null : _simpan,
          child: Text(_menyimpan ? 'Menyimpan...' : 'Simpan'),
        ),
      ],
    );
  }
}

class _HargaGrosirSection extends ConsumerStatefulWidget {
  const _HargaGrosirSection({required this.produkId});

  final String produkId;

  @override
  ConsumerState<_HargaGrosirSection> createState() => _HargaGrosirSectionState();
}

class _HargaGrosirSectionState extends ConsumerState<_HargaGrosirSection> {
  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SectionHeader(label: 'Harga grosir (tier)'),
              IconButton(
                key: const Key('produkLanjutan.tambahHargaGrosir'),
                icon: const Icon(Icons.add_circle_outline),
                onPressed: () async {
                  final berubah = await showDialog<bool>(
                    context: context,
                    builder: (context) => _HargaGrosirDialog(produkId: widget.produkId),
                  );
                  if (berubah == true) setState(() {});
                },
              ),
            ],
          ),
          FutureBuilder<List<HargaGrosirRow>>(
            key: ValueKey(DateTime.now().microsecondsSinceEpoch),
            future: ref.read(hargaDaoProvider).hargaGrosirUntukSatuProduk(widget.produkId),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              final daftar = snapshot.data!;
              if (daftar.isEmpty) {
                return const EmptyState(icon: Icons.sell_outlined, message: 'Belum ada harga grosir');
              }
              return Column(
                children: [
                  for (final item in daftar)
                    Material(
                      type: MaterialType.transparency,
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('Beli >= ${item.minQty}'),
                        trailing: Text('Rp${item.harga}'),
                        onTap: () async {
                          final berubah = await showDialog<bool>(
                            context: context,
                            builder: (context) => _HargaGrosirDialog(produkId: widget.produkId, itemEdit: item),
                          );
                          if (berubah == true) setState(() {});
                        },
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _HargaGrosirDialog extends ConsumerStatefulWidget {
  const _HargaGrosirDialog({required this.produkId, this.itemEdit});

  final String produkId;
  final HargaGrosirRow? itemEdit;

  @override
  ConsumerState<_HargaGrosirDialog> createState() => _HargaGrosirDialogState();
}

class _HargaGrosirDialogState extends ConsumerState<_HargaGrosirDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _minQtyController = TextEditingController(text: widget.itemEdit?.minQty.toString() ?? '');
  late final _hargaController = TextEditingController(text: widget.itemEdit?.harga.toString() ?? '');
  bool _menyimpan = false;
  bool _menghapus = false;
  String? _error;

  bool get _modeEdit => widget.itemEdit != null;

  @override
  void dispose() {
    _minQtyController.dispose();
    _hargaController.dispose();
    super.dispose();
  }

  Future<void> _simpan() async {
    if (!_formKey.currentState!.validate()) return;
    final sesi = await _ambilSesi(ref);
    if (sesi == null) {
      setState(() => _error = 'Device belum pairing ke backend.');
      return;
    }
    setState(() {
      _menyimpan = true;
      _error = null;
    });
    try {
      final Map<String, dynamic> hasil;
      if (_modeEdit) {
        hasil = await ref.read(backendApiProvider).patchJson(
              accessToken: sesi.accessToken,
              path: '/produk/${widget.produkId}/harga-grosir/${widget.itemEdit!.id}',
              body: {'min_qty': _minQtyController.text.trim(), 'harga': _hargaController.text.trim()},
            ) as Map<String, dynamic>;
      } else {
        hasil = await ref.read(backendApiProvider).postJson(
              accessToken: sesi.accessToken,
              path: '/produk/${widget.produkId}/harga-grosir',
              body: {'min_qty': _minQtyController.text.trim(), 'harga': _hargaController.text.trim()},
            ) as Map<String, dynamic>;
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      await ref.read(hargaDaoProvider).upsertHargaGrosir(HargaGrosirCompanion.insert(
            id: hasil['id'] as String,
            produkId: widget.produkId,
            minQty: double.parse(hasil['min_qty'].toString()),
            harga: double.parse(hasil['harga'].toString()).round(),
            createdAt: now,
            updatedAt: now,
          ));
      if (mounted) Navigator.of(context).pop(true);
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
        title: const Text('Hapus harga grosir?'),
        content: Text('Tier "Beli >= ${widget.itemEdit!.minQty}" akan dihapus.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Hapus')),
        ],
      ),
    );
    if (konfirmasi != true) return;
    final sesi = await _ambilSesi(ref);
    if (sesi == null) return;
    setState(() => _menghapus = true);
    try {
      await ref.read(backendApiProvider).deleteJson(
            accessToken: sesi.accessToken,
            path: '/produk/${widget.produkId}/harga-grosir/${widget.itemEdit!.id}',
          );
      await ref.read(hargaDaoProvider).hapusHargaGrosirLokal(widget.itemEdit!.id);
      if (mounted) Navigator.of(context).pop(true);
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
      title: Text(_modeEdit ? 'Ubah Harga Grosir' : 'Tambah Harga Grosir'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!online) const OfflineNoticeBanner(),
            if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
            TextFormField(
              key: const Key('hargaGrosirDialog.minQty'),
              controller: _minQtyController,
              decoration: const InputDecoration(labelText: 'Minimal qty beli'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (value) {
                if (value == null || value.trim().isEmpty) return 'Wajib diisi';
                if (double.tryParse(value) == null) return 'Harus berupa angka';
                return null;
              },
            ),
            TextFormField(
              key: const Key('hargaGrosirDialog.harga'),
              controller: _hargaController,
              decoration: const InputDecoration(labelText: 'Harga per unit', prefixText: 'Rp '),
              keyboardType: TextInputType.number,
              validator: (value) {
                if (value == null || value.trim().isEmpty) return 'Wajib diisi';
                if (double.tryParse(value) == null) return 'Harus berupa angka';
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        if (_modeEdit)
          TextButton(
            key: const Key('hargaGrosirDialog.hapus'),
            onPressed: _menghapus || !online ? null : _hapus,
            child: const Text('Hapus'),
          ),
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Batal')),
        FilledButton(
          key: const Key('hargaGrosirDialog.simpan'),
          onPressed: _menyimpan || !online ? null : _simpan,
          child: Text(_menyimpan ? 'Menyimpan...' : 'Simpan'),
        ),
      ],
    );
  }
}

class _HargaOutletSection extends ConsumerStatefulWidget {
  const _HargaOutletSection({required this.produkId});

  final String produkId;

  @override
  ConsumerState<_HargaOutletSection> createState() => _HargaOutletSectionState();
}

class _HargaOutletSectionState extends ConsumerState<_HargaOutletSection> {
  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SectionHeader(label: 'Harga per outlet'),
              IconButton(
                key: const Key('produkLanjutan.tambahHargaOutlet'),
                icon: const Icon(Icons.add_circle_outline),
                onPressed: () async {
                  final berubah = await showDialog<bool>(
                    context: context,
                    builder: (context) => _HargaOutletDialog(produkId: widget.produkId),
                  );
                  if (berubah == true) setState(() {});
                },
              ),
            ],
          ),
          FutureBuilder<List<HargaOutletRow>>(
            key: ValueKey(DateTime.now().microsecondsSinceEpoch),
            future: ref.read(hargaDaoProvider).hargaOutletUntukSatuProduk(widget.produkId),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              final daftar = snapshot.data!;
              if (daftar.isEmpty) {
                return const EmptyState(icon: Icons.store_outlined, message: 'Belum ada harga khusus outlet');
              }
              return Column(
                children: [
                  for (final item in daftar)
                    Material(
                      type: MaterialType.transparency,
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(item.outletId),
                        trailing: Text('Rp${item.hargaJual}'),
                        onTap: () async {
                          final berubah = await showDialog<bool>(
                            context: context,
                            builder: (context) => _HargaOutletDialog(produkId: widget.produkId, itemEdit: item),
                          );
                          if (berubah == true) setState(() {});
                        },
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _HargaOutletDialog extends ConsumerStatefulWidget {
  const _HargaOutletDialog({required this.produkId, this.itemEdit});

  final String produkId;
  final HargaOutletRow? itemEdit;

  @override
  ConsumerState<_HargaOutletDialog> createState() => _HargaOutletDialogState();
}

class _HargaOutletDialogState extends ConsumerState<_HargaOutletDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _hargaController = TextEditingController(text: widget.itemEdit?.hargaJual.toString() ?? '');
  bool _memuatOutlet = true;
  List<Map<String, dynamic>> _daftarOutlet = [];
  String? _outletTerpilih;
  bool _menyimpan = false;
  bool _menghapus = false;
  String? _error;

  bool get _modeEdit => widget.itemEdit != null;

  @override
  void initState() {
    super.initState();
    if (!_modeEdit) _muatOutlet();
  }

  Future<void> _muatOutlet() async {
    try {
      final sesi = await _ambilSesi(ref);
      if (sesi == null) return;
      final hasil = await ref.read(backendApiProvider).getJson(accessToken: sesi.accessToken, path: '/outlets');
      _daftarOutlet = (hasil as List).cast<Map<String, dynamic>>();
    } catch (e) {
      _error = 'Gagal memuat outlet: $e';
    } finally {
      if (mounted) setState(() => _memuatOutlet = false);
    }
  }

  @override
  void dispose() {
    _hargaController.dispose();
    super.dispose();
  }

  Future<void> _simpan() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_modeEdit && _outletTerpilih == null) {
      setState(() => _error = 'Pilih outlet dulu');
      return;
    }
    final sesi = await _ambilSesi(ref);
    if (sesi == null) {
      setState(() => _error = 'Device belum pairing ke backend.');
      return;
    }
    setState(() {
      _menyimpan = true;
      _error = null;
    });
    try {
      final Map<String, dynamic> hasil;
      if (_modeEdit) {
        hasil = await ref.read(backendApiProvider).patchJson(
              accessToken: sesi.accessToken,
              path: '/produk/${widget.produkId}/harga-outlet/${widget.itemEdit!.id}',
              body: {'harga_jual': _hargaController.text.trim()},
            ) as Map<String, dynamic>;
      } else {
        hasil = await ref.read(backendApiProvider).postJson(
              accessToken: sesi.accessToken,
              path: '/produk/${widget.produkId}/harga-outlet',
              body: {'outlet_id': _outletTerpilih, 'harga_jual': _hargaController.text.trim()},
            ) as Map<String, dynamic>;
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      await ref.read(hargaDaoProvider).upsertHargaOutlet(HargaOutletCompanion.insert(
            id: hasil['id'] as String,
            outletId: hasil['outlet_id'] as String,
            produkId: widget.produkId,
            hargaJual: double.parse(hasil['harga_jual'].toString()).round(),
            createdAt: now,
            updatedAt: now,
          ));
      if (mounted) Navigator.of(context).pop(true);
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
        title: const Text('Hapus harga outlet?'),
        content: Text('Harga khusus utk outlet "${widget.itemEdit!.outletId}" akan dihapus.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Hapus')),
        ],
      ),
    );
    if (konfirmasi != true) return;
    final sesi = await _ambilSesi(ref);
    if (sesi == null) return;
    setState(() => _menghapus = true);
    try {
      await ref.read(backendApiProvider).deleteJson(
            accessToken: sesi.accessToken,
            path: '/produk/${widget.produkId}/harga-outlet/${widget.itemEdit!.id}',
          );
      await ref.read(hargaDaoProvider).hapusHargaOutletLokal(widget.itemEdit!.id);
      if (mounted) Navigator.of(context).pop(true);
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
      title: Text(_modeEdit ? 'Ubah Harga Outlet' : 'Tambah Harga Outlet'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!online) const OfflineNoticeBanner(),
            if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
            if (_modeEdit)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(widget.itemEdit!.outletId, style: const TextStyle(fontWeight: FontWeight.bold)),
              )
            else if (_memuatOutlet)
              const LinearProgressIndicator()
            else
              DropdownButtonFormField<String>(
                key: const Key('hargaOutletDialog.outlet'),
                decoration: const InputDecoration(labelText: 'Outlet'),
                items: _daftarOutlet
                    .map((o) => DropdownMenuItem(value: o['id'] as String, child: Text(o['nama'] as String)))
                    .toList(),
                onChanged: (value) => setState(() => _outletTerpilih = value),
              ),
            TextFormField(
              key: const Key('hargaOutletDialog.harga'),
              controller: _hargaController,
              decoration: const InputDecoration(labelText: 'Harga jual', prefixText: 'Rp '),
              keyboardType: TextInputType.number,
              validator: (value) {
                if (value == null || value.trim().isEmpty) return 'Wajib diisi';
                if (double.tryParse(value) == null) return 'Harus berupa angka';
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        if (_modeEdit)
          TextButton(
            key: const Key('hargaOutletDialog.hapus'),
            onPressed: _menghapus || !online ? null : _hapus,
            child: const Text('Hapus'),
          ),
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Batal')),
        FilledButton(
          key: const Key('hargaOutletDialog.simpan'),
          onPressed: _menyimpan || !online ? null : _simpan,
          child: Text(_menyimpan ? 'Menyimpan...' : 'Simpan'),
        ),
      ],
    );
  }
}
