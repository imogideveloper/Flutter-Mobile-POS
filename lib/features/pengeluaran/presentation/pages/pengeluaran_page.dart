import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/network/auth_session_store.dart';
import '../../../../core/network/backend_exception.dart';
import '../../../../core/network/dio_backend_api.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/id_generator.dart';
import '../../../../core/utils/rupiah_input_formatter.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../domain/pengeluaran.dart';

/// Pengeluaran & biaya operasional (IMOGI no. 67). Pencatatan langsung ke server (butuh internet),
/// belum offline. Hanya role dengan izin laporan.lihat (Owner/Manajer) yang bisa membukanya.
class PengeluaranPage extends ConsumerStatefulWidget {
  const PengeluaranPage({super.key});

  @override
  ConsumerState<PengeluaranPage> createState() => _PengeluaranPageState();
}

class _PengeluaranPageState extends ConsumerState<PengeluaranPage> {
  RentangPengeluaran _rentang = RentangPengeluaran.hariIni;
  DaftarPengeluaran? _data;
  String? _error;
  bool _memuat = true;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<SesiBackend?> _sesi() => ref.read(authSessionStoreProvider).muat();

  Future<void> _muat() async {
    setState(() {
      _memuat = true;
      _error = null;
    });
    try {
      final sesi = await _sesi();
      if (sesi == null) throw const BackendException(message: 'Perangkat belum terhubung ke server');
      final (dari, sampai) = _rentang.tanggal(DateTime.now());
      final json = await ref.read(backendApiProvider).daftarPengeluaran(
            accessToken: sesi.accessToken,
            dari: tanggalApi(dari),
            sampai: tanggalApi(sampai),
          );
      _data = DaftarPengeluaran.dariJson(json);
    } on BackendException catch (e) {
      _error = e.tidakAdaKoneksi ? 'Butuh internet untuk melihat pengeluaran.' : e.message;
    } catch (e) {
      _error = 'Gagal memuat: $e';
    } finally {
      if (mounted) setState(() => _memuat = false);
    }
  }

  Future<void> _tambah() async {
    final tersimpan = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _FormPengeluaran(),
    );
    if (tersimpan == true) _muat();
  }

  Future<void> _hapus(PengeluaranItem item) async {
    final yakin = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus pengeluaran?'),
        content: Text('${labelKategoriPengeluaran(item.kategori)} Rp ${formatRupiahDigits(item.jumlah)}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Hapus')),
        ],
      ),
    );
    if (yakin != true) return;
    try {
      final sesi = await _sesi();
      if (sesi == null) return;
      await ref.read(backendApiProvider).hapusPengeluaran(accessToken: sesi.accessToken, pengeluaranId: item.id);
      _muat();
    } on BackendException catch (e) {
      if (mounted) showAppToast(context, message: e.message, variant: ToastVariant.danger);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return Scaffold(
      appBar: AppBar(title: const Text('Pengeluaran')),
      floatingActionButton: FloatingActionButton(
        key: const Key('pengeluaran.tambah'),
        onPressed: _tambah,
        tooltip: 'Catat pengeluaran',
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.md, AppSpacing.xl, AppSpacing.sm),
            child: Wrap(
              spacing: AppSpacing.sm,
              children: [
                for (final r in RentangPengeluaran.values)
                  ChoiceChip(
                    key: Key('pengeluaran.rentang.${r.name}'),
                    label: Text(r.label),
                    selected: _rentang == r,
                    onSelected: (_) {
                      setState(() => _rentang = r);
                      _muat();
                    },
                  ),
              ],
            ),
          ),
          Expanded(child: _isi(data)),
        ],
      ),
    );
  }

  Widget _isi(DaftarPengeluaran? data) {
    if (_memuat && data == null) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, key: const Key('pengeluaran.error'), textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton(onPressed: _muat, child: const Text('Coba lagi')),
            ],
          ),
        ),
      );
    }
    if (data == null || data.item.isEmpty) {
      return const EmptyState(icon: Icons.receipt_outlined, message: 'Belum ada pengeluaran pada rentang ini');
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, 96),
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Total pengeluaran', style: AppTypography.secondary),
              Text('Rp ${formatRupiahDigits(data.total)}',
                  key: const Key('pengeluaran.total'), style: AppTypography.headerTitle.copyWith(fontSize: 22)),
              const SizedBox(height: AppSpacing.sm),
              for (final e in data.perKategori.entries)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(
                    children: [
                      Expanded(child: Text(labelKategoriPengeluaran(e.key))),
                      Text('Rp ${formatRupiahDigits(e.value)}', style: AppTypography.bodyEmphasis),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        for (final item in data.item)
          ListTile(
            key: Key('pengeluaran.item.${item.id}'),
            contentPadding: EdgeInsets.zero,
            title: Text(labelKategoriPengeluaran(item.kategori)),
            subtitle: Text([
              DateFormat('d MMM yyyy', 'id_ID').format(DateTime.parse(item.tanggal)),
              if (item.catatan != null && item.catatan!.isNotEmpty) item.catatan!,
            ].join(' · ')),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Rp ${formatRupiahDigits(item.jumlah)}', style: AppTypography.bodyEmphasis),
                IconButton(
                  key: Key('pengeluaran.hapus.${item.id}'),
                  tooltip: 'Hapus',
                  icon: const Icon(Icons.delete_outline, color: AppColors.dangerText),
                  onPressed: () => _hapus(item),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _FormPengeluaran extends ConsumerStatefulWidget {
  const _FormPengeluaran();

  @override
  ConsumerState<_FormPengeluaran> createState() => _FormPengeluaranState();
}

class _FormPengeluaranState extends ConsumerState<_FormPengeluaran> {
  final _jumlah = TextEditingController();
  final _catatan = TextEditingController();
  String _kategori = 'belanja_bahan';
  DateTime _tanggal = DateTime.now();
  bool _menyimpan = false;
  String? _error;
  // Dibuat sekali per form: ketuk Simpan dua kali tidak menggandakan catatan (idempoten di server).
  final String _id = generateId();

  @override
  void dispose() {
    _jumlah.dispose();
    _catatan.dispose();
    super.dispose();
  }

  Future<void> _simpan() async {
    final nilai = parseRupiahInput(_jumlah.text);
    if (nilai == null || nilai <= 0) {
      setState(() => _error = 'Isi jumlah pengeluaran');
      return;
    }
    setState(() {
      _menyimpan = true;
      _error = null;
    });
    try {
      final sesi = await ref.read(authSessionStoreProvider).muat();
      if (sesi == null) throw const BackendException(message: 'Perangkat belum terhubung ke server');
      await ref.read(backendApiProvider).catatPengeluaran(
        accessToken: sesi.accessToken,
        body: {
          'id': _id,
          'outlet_id': sesi.outletId,
          'tanggal': tanggalApi(_tanggal),
          'kategori': _kategori,
          'jumlah': nilai,
          if (_catatan.text.trim().isNotEmpty) 'catatan': _catatan.text.trim(),
        },
      );
      if (mounted) Navigator.pop(context, true);
    } on BackendException catch (e) {
      if (mounted) {
        setState(() => _error = e.tidakAdaKoneksi ? 'Butuh internet untuk mencatat pengeluaran.' : e.message);
      }
    } finally {
      if (mounted) setState(() => _menyimpan = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xl + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Catat pengeluaran', style: AppTypography.cardTitle),
          const SizedBox(height: AppSpacing.md),
          DropdownButtonFormField<String>(
            key: const Key('pengeluaranForm.kategori'),
            initialValue: _kategori,
            decoration: const InputDecoration(labelText: 'Kategori'),
            items: [
              for (final e in kategoriPengeluaran.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
            ],
            onChanged: (v) => setState(() => _kategori = v ?? _kategori),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            key: const Key('pengeluaranForm.jumlah'),
            controller: _jumlah,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, RupiahInputFormatter()],
            decoration: const InputDecoration(labelText: 'Jumlah', prefixText: 'Rp '),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            key: const Key('pengeluaranForm.catatan'),
            controller: _catatan,
            maxLength: 300,
            decoration: const InputDecoration(labelText: 'Catatan (opsional)', counterText: ''),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            icon: const Icon(Icons.event_outlined, size: 18),
            label: Text('Tanggal: ${DateFormat('d MMM yyyy', 'id_ID').format(_tanggal)}'),
            onPressed: () async {
              final pilih = await showDatePicker(
                context: context,
                initialDate: _tanggal,
                firstDate: DateTime(2020),
                lastDate: DateTime.now(),
              );
              if (pilih != null) setState(() => _tanggal = pilih);
            },
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(_error!, key: const Key('pengeluaranForm.error'), style: const TextStyle(color: AppColors.dangerText)),
          ],
          const SizedBox(height: AppSpacing.md),
          FilledButton(
            key: const Key('pengeluaranForm.simpan'),
            onPressed: _menyimpan ? null : _simpan,
            child: Text(_menyimpan ? 'Menyimpan...' : 'Simpan'),
          ),
        ],
      ),
    );
  }
}
