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
import '../../../../core/widgets/fitur_terkunci.dart';
import '../../../../core/widgets/offline_notice_banner.dart';
import '../../../produk/domain/produk.dart';
import '../../../produk/presentation/providers/produk_providers.dart';
import '../../data/local/tables/promo_table.dart' show PromoCakupan, PromoTipe;
import '../../domain/promo.dart';
import '../providers/promo_providers.dart';

const _labelTipePromo = {PromoTipe.persen: 'Persen (%)', PromoTipe.nominal: 'Nominal (Rp)'};
const _labelCakupanPromo = {PromoCakupan.transaksi: 'Seluruh transaksi', PromoCakupan.produk: 'Produk tertentu'};

/// Tahap 5 C.5 - "daftar, buat, edit, nonaktifkan; pilih produk dan
/// outlet". Sama pola online-direct dgn PajakFormPage/PelangganFormPage.
class PromoFormPage extends ConsumerStatefulWidget {
  const PromoFormPage({super.key, this.promoEdit});

  final Promo? promoEdit;

  @override
  ConsumerState<PromoFormPage> createState() => _PromoFormPageState();
}

class _PromoFormPageState extends ConsumerState<PromoFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final _namaController = TextEditingController(text: widget.promoEdit?.nama ?? '');
  late final _kodeController = TextEditingController(text: widget.promoEdit?.kode ?? '');
  late final _nilaiController =
      TextEditingController(text: widget.promoEdit != null ? _fmt(widget.promoEdit!.nilai) : '');
  late final _minBelanjaController =
      TextEditingController(text: (widget.promoEdit?.minBelanja ?? 0).toString());
  late final _maksDiskonController =
      TextEditingController(text: widget.promoEdit?.maksDiskon?.toString() ?? '');
  late PromoTipe _tipe = widget.promoEdit?.tipe ?? PromoTipe.persen;
  late PromoCakupan _cakupan = widget.promoEdit?.cakupan ?? PromoCakupan.transaksi;
  late bool _aktif = widget.promoEdit?.aktif ?? true;
  late bool _khususUlangTahun = widget.promoEdit?.khususUlangTahun ?? false;
  bool _menyimpan = false;
  bool _menghapus = false;
  String? _errorServer;

  Set<String> _produkTerpilih = {};
  bool _memuatProduk = false;

  bool get _modeEdit => widget.promoEdit != null;

  static String _fmt(double v) => v.truncateToDouble() == v ? v.toStringAsFixed(0) : v.toString();

  @override
  void initState() {
    super.initState();
    if (_modeEdit) _muatProdukTerpilih();
  }

  @override
  void dispose() {
    _namaController.dispose();
    _kodeController.dispose();
    _nilaiController.dispose();
    _minBelanjaController.dispose();
    _maksDiskonController.dispose();
    super.dispose();
  }

  Future<void> _muatProdukTerpilih() async {
    setState(() => _memuatProduk = true);
    try {
      final sesi = await ref.read(authSessionStoreProvider).muat();
      if (sesi == null) return;
      final hasil = await ref.read(backendApiProvider).getJson(
            accessToken: sesi.accessToken,
            path: '/promo/${widget.promoEdit!.id}/produk',
          );
      _produkTerpilih = (hasil as List).map((e) => e.toString()).toSet();
    } catch (_) {
      // Diam-diam - pratinjau produk tidak krusial, form tetap bisa dipakai.
    } finally {
      if (mounted) setState(() => _memuatProduk = false);
    }
  }

  Future<void> _pilihProduk() async {
    final semuaProduk = await ref.read(produkAktifProvider.future);
    if (!mounted) return;
    final hasil = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _ProdukPickerSheet(semuaProduk: semuaProduk, terpilihAwal: _produkTerpilih),
    );
    if (hasil == null) return;

    final sesi = await ref.read(authSessionStoreProvider).muat();
    if (sesi == null) return;
    try {
      await ref.read(backendApiProvider).putJsonIds(
            accessToken: sesi.accessToken,
            path: '/promo/${widget.promoEdit!.id}/produk',
            ids: hasil.toList(),
          );
      await ref.read(promoDaoProvider).aturProdukLokal(widget.promoEdit!.id, hasil.toList());
      setState(() => _produkTerpilih = hasil);
    } catch (e) {
      if (mounted) {
        showAppToast(context, message: 'Gagal menyimpan produk: $e', variant: ToastVariant.danger);
      }
    }
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
        'kode': _kodeController.text.trim().isEmpty ? null : _kodeController.text.trim(),
        'tipe': _tipe == PromoTipe.persen ? 'persen' : 'nominal',
        'nilai': _nilaiController.text.trim(),
        'cakupan': _cakupan == PromoCakupan.produk ? 'produk' : 'transaksi',
        'min_belanja': _minBelanjaController.text.trim().isEmpty ? '0' : _minBelanjaController.text.trim(),
        'maks_diskon': _maksDiskonController.text.trim().isEmpty ? null : _maksDiskonController.text.trim(),
        if (_modeEdit) 'aktif': _aktif,
        'khusus_ulang_tahun': _khususUlangTahun,
      };
      final Map<String, dynamic> hasil;
      if (_modeEdit) {
        hasil = await ref.read(backendApiProvider).patchJson(
              accessToken: sesi.accessToken,
              path: '/promo/${widget.promoEdit!.id}',
              body: body,
            ) as Map<String, dynamic>;
      } else {
        hasil = await ref.read(backendApiProvider).postJson(
              accessToken: sesi.accessToken,
              path: '/promo',
              body: body,
            ) as Map<String, dynamic>;
      }

      final tokoId = ref.read(currentTokoIdProvider);
      final now = DateTime.now().millisecondsSinceEpoch;
      await ref.read(promoDaoProvider).upsertPromo(PromoCompanion.insert(
            id: hasil['id'] as String,
            tokoId: tokoId,
            nama: hasil['nama'] as String,
            kode: Value(hasil['kode'] as String?),
            tipe: hasil['tipe'] == 'nominal' ? PromoTipe.nominal : PromoTipe.persen,
            nilai: double.parse(hasil['nilai'].toString()),
            cakupan: Value(hasil['cakupan'] == 'produk' ? PromoCakupan.produk : PromoCakupan.transaksi),
            minBelanja: Value(double.parse(hasil['min_belanja'].toString()).round()),
            maksDiskon: Value(
              hasil['maks_diskon'] == null ? null : double.parse(hasil['maks_diskon'].toString()).round(),
            ),
            aktif: Value(hasil['aktif'] as bool),
            khususUlangTahun: Value((hasil['khusus_ulang_tahun'] as bool?) ?? false),
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
        title: const Text('Hapus promo?'),
        content: Text('"${widget.promoEdit!.nama}" akan dinonaktifkan.'),
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
            path: '/promo/${widget.promoEdit!.id}',
          );
      await ref.read(promoDaoProvider).nonaktifkanLokal(widget.promoEdit!.id);
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
        title: Text(_modeEdit ? 'Ubah Promo' : 'Tambah Promo'),
        actions: [
          if (_modeEdit)
            IconButton(
              key: const Key('promoForm.hapus'),
              onPressed: _menghapus || !online ? null : _hapus,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          key: const Key('promoForm.scrollView'),
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
                  key: const Key('promoForm.nama'),
                  controller: _namaController,
                  decoration: const InputDecoration(labelText: 'Nama promo'),
                  validator: (value) =>
                      (value == null || value.trim().isEmpty) ? 'Nama wajib diisi' : null,
                ),
                const SizedBox(height: AppSpacing.lg),
                TextFormField(
                  key: const Key('promoForm.kode'),
                  controller: _kodeController,
                  decoration: const InputDecoration(labelText: 'Kode voucher (opsional)'),
                  textCapitalization: TextCapitalization.characters,
                ),
                const SizedBox(height: AppSpacing.lg),
                DropdownButtonFormField<PromoTipe>(
                  key: const Key('promoForm.tipe'),
                  initialValue: _tipe,
                  decoration: const InputDecoration(labelText: 'Tipe diskon'),
                  items: PromoTipe.values
                      .map((tipe) => DropdownMenuItem(value: tipe, child: Text(_labelTipePromo[tipe]!)))
                      .toList(),
                  onChanged: (value) => setState(() => _tipe = value ?? _tipe),
                ),
                const SizedBox(height: AppSpacing.lg),
                TextFormField(
                  key: const Key('promoForm.nilai'),
                  controller: _nilaiController,
                  decoration: const InputDecoration(labelText: 'Nilai diskon'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return 'Nilai wajib diisi';
                    if (double.tryParse(value) == null) return 'Nilai harus berupa angka';
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.lg),
                DropdownButtonFormField<PromoCakupan>(
                  key: const Key('promoForm.cakupan'),
                  initialValue: _cakupan,
                  decoration: const InputDecoration(labelText: 'Cakupan'),
                  items: PromoCakupan.values
                      .map((c) => DropdownMenuItem(value: c, child: Text(_labelCakupanPromo[c]!)))
                      .toList(),
                  onChanged: (value) => setState(() => _cakupan = value ?? _cakupan),
                ),
                const SizedBox(height: AppSpacing.lg),
                TextFormField(
                  key: const Key('promoForm.minBelanja'),
                  controller: _minBelanjaController,
                  decoration: const InputDecoration(labelText: 'Minimal belanja', prefixText: 'Rp '),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return null;
                    if (int.tryParse(value.trim()) == null) return 'Harus berupa angka';
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.lg),
                TextFormField(
                  key: const Key('promoForm.maksDiskon'),
                  controller: _maksDiskonController,
                  decoration: const InputDecoration(
                    labelText: 'Maksimal diskon (opsional)',
                    prefixText: 'Rp ',
                    helperText: 'Kosongkan jika tidak dibatasi',
                  ),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return null;
                    if (int.tryParse(value.trim()) == null) return 'Harus berupa angka';
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.lg),
                FiturTerkunci(
                  kode: 'birthday_promo',
                  child: Material(
                    type: MaterialType.transparency,
                    child: SwitchListTile(
                      key: const Key('promoForm.khususUlangTahun'),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Khusus ulang tahun pelanggan'),
                      subtitle: const Text('Hanya bisa dipilih kasir untuk pelanggan yang berulang tahun hari ini'),
                      value: _khususUlangTahun,
                      onChanged: (value) => setState(() => _khususUlangTahun = value),
                    ),
                  ),
                ),
                if (_modeEdit) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Material(
                    type: MaterialType.transparency,
                    child: SwitchListTile(
                      key: const Key('promoForm.aktif'),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Aktif'),
                      value: _aktif,
                      onChanged: (value) => setState(() => _aktif = value),
                    ),
                  ),
                  if (_cakupan == PromoCakupan.produk) ...[
                    const SizedBox(height: AppSpacing.lg),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _memuatProduk
                                ? 'Memuat produk...'
                                : 'Produk berlaku: ${_produkTerpilih.length} dipilih',
                          ),
                        ),
                        OutlinedButton(
                          key: const Key('promoForm.pilihProduk'),
                          onPressed: online ? _pilihProduk : null,
                          child: const Text('Pilih produk'),
                        ),
                      ],
                    ),
                  ],
                ],
                const SizedBox(height: AppSpacing.xxxl),
                AppPrimaryButton(
                  key: const Key('promoForm.simpan'),
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

class _ProdukPickerSheet extends StatefulWidget {
  const _ProdukPickerSheet({required this.semuaProduk, required this.terpilihAwal});

  final List<Produk> semuaProduk;
  final Set<String> terpilihAwal;

  @override
  State<_ProdukPickerSheet> createState() => _ProdukPickerSheetState();
}

class _ProdukPickerSheetState extends State<_ProdukPickerSheet> {
  final Set<String> _terpilih = {};

  @override
  void initState() {
    super.initState();
    _terpilih.addAll(widget.terpilihAwal);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      builder: (context, scrollController) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Pilih produk', style: TextStyle(fontWeight: FontWeight.bold)),
                TextButton(
                  key: const Key('produkPicker.selesai'),
                  onPressed: () => Navigator.of(context).pop(_terpilih),
                  child: const Text('Selesai'),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              itemCount: widget.semuaProduk.length,
              itemBuilder: (context, index) {
                final produk = widget.semuaProduk[index];
                return CheckboxListTile(
                  key: Key('produkPicker.item.${produk.id}'),
                  title: Text(produk.nama),
                  value: _terpilih.contains(produk.id),
                  onChanged: (checked) => setState(() {
                    if (checked ?? false) {
                      _terpilih.add(produk.id);
                    } else {
                      _terpilih.remove(produk.id);
                    }
                  }),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
