import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/network/auth_session_store.dart';
import '../../../../core/network/dio_backend_api.dart';
import '../../../../core/network/sync_repository.dart';
import '../../../../core/providers/session_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/fitur_terkunci.dart';
import '../../data/local/stok_dao.dart';
import '../../domain/kedaluwarsa.dart';
import '../providers/stok_providers.dart';

final _formatTanggal = DateFormat('d MMM yyyy', 'id_ID');
final _formatQty = NumberFormat.decimalPattern('id_ID');

/// Pengingat kedaluwarsa produk (IMOGI no. 50): daftar batch dengan penanda sudah lewat / segera.
/// Batch hanya pengingat; penjualan belum mengurangi sisa batch.
class KedaluwarsaPage extends ConsumerWidget {
  const KedaluwarsaPage({super.key, this.sekarang});

  /// Untuk tes; null = waktu sekarang.
  final DateTime? sekarang;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final outletId = ref.watch(currentOutletIdProvider);
    final batch = ref.watch(batchKedaluwarsaProvider(outletId));
    final waktu = sekarang ?? DateTime.now();

    return Scaffold(
      appBar: AppBar(title: const Text('Kedaluwarsa produk')),
      floatingActionButton: FiturTerkunci(
        kode: 'pengingat_kedaluwarsa',
        child: FloatingActionButton.extended(
          key: const Key('kedaluwarsa.tambah'),
          onPressed: () => unawaited(_tambah(context, ref, outletId)),
          icon: const Icon(Icons.add),
          label: const Text('Catat batch'),
        ),
      ),
      body: batch.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Gagal memuat: $e')),
        data: (items) {
          if (items.isEmpty) {
            return const EmptyState(
              icon: Icons.event_busy_outlined,
              message: 'Belum ada batch yang dicatat. Ketuk "Catat batch" untuk mulai.',
            );
          }
          final lewat = items
              .where((b) => statusKedaluwarsa(
                    tanggalKedaluwarsaMs: b.batch.tanggalKedaluwarsa,
                    ingatkanHari: b.batch.ingatkanHari,
                    sekarang: waktu,
                  ) ==
                  StatusKedaluwarsa.sudahLewat)
              .length;
          final segera = items
              .where((b) => statusKedaluwarsa(
                    tanggalKedaluwarsaMs: b.batch.tanggalKedaluwarsa,
                    ingatkanHari: b.batch.ingatkanHari,
                    sekarang: waktu,
                  ) ==
                  StatusKedaluwarsa.segera)
              .length;
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            children: [
              AppCard(
                child: Row(
                  children: [
                    _Ringkas(label: 'Sudah lewat', nilai: '$lewat', kunci: 'kedaluwarsa.lewat', warna: AppColors.dangerText),
                    _Ringkas(label: 'Segera', nilai: '$segera', kunci: 'kedaluwarsa.segera', warna: AppColors.warningTextStrong),
                    _Ringkas(label: 'Semua batch', nilai: '${items.length}', kunci: 'kedaluwarsa.semua'),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var i = 0; i < items.length; i++)
                      _BarisBatch(item: items[i], sekarang: waktu, garis: i < items.length - 1),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _tambah(BuildContext context, WidgetRef ref, String outletId) async {
    final stok = ref.read(stokOutletProvider(outletId)).value ?? const [];
    final produk = <String, String>{for (final s in stok) s.produkId: s.produkNama};
    if (produk.isEmpty) {
      showAppToast(context, message: 'Belum ada produk dengan stok di outlet ini', variant: ToastVariant.warning);
      return;
    }
    final body = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _DialogBatch(outletId: outletId, produk: produk),
    );
    if (body == null || !context.mounted) return;
    final sesi = await ref.read(authSessionStoreProvider).muat();
    if (sesi == null) return;
    try {
      await ref.read(backendApiProvider).tambahBatchStok(accessToken: sesi.accessToken, body: body);
      unawaited(ref.read(syncRepositoryProvider).jalankan());
      if (context.mounted) showAppToast(context, message: 'Batch dicatat', variant: ToastVariant.success);
    } catch (e) {
      if (context.mounted) showAppToast(context, message: 'Gagal mencatat batch: $e', variant: ToastVariant.danger);
    }
  }
}

class _Ringkas extends StatelessWidget {
  const _Ringkas({required this.label, required this.nilai, required this.kunci, this.warna});

  final String label;
  final String nilai;
  final String kunci;
  final Color? warna;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          children: [
            Text(label, style: AppTypography.secondary, textAlign: TextAlign.center),
            Text(nilai, key: Key(kunci), style: AppTypography.bodyEmphasis.copyWith(color: warna)),
          ],
        ),
      );
}

class _BarisBatch extends ConsumerWidget {
  const _BarisBatch({required this.item, required this.sekarang, required this.garis});

  final BatchDenganProduk item;
  final DateTime sekarang;
  final bool garis;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = item.batch;
    final status = statusKedaluwarsa(
      tanggalKedaluwarsaMs: b.tanggalKedaluwarsa,
      ingatkanHari: b.ingatkanHari,
      sekarang: sekarang,
    );
    final warna = switch (status) {
      StatusKedaluwarsa.sudahLewat => AppColors.dangerText,
      StatusKedaluwarsa.segera => AppColors.warningTextStrong,
      StatusKedaluwarsa.aman => AppColors.primaryDark,
    };
    final tanggal = DateTime.fromMillisecondsSinceEpoch(b.tanggalKedaluwarsa, isUtc: true);
    final sisa = sisaHariKedaluwarsa(b.tanggalKedaluwarsa, sekarang);
    return Container(
      key: Key('kedaluwarsa.baris.${b.id}'),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
      decoration: garis
          ? const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.borderDefault)))
          : null,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.produk.nama, style: AppTypography.bodyEmphasis),
                Text(
                  '${b.nomorBatch == null ? 'Tanpa nomor batch' : 'Batch ${b.nomorBatch}'} · ${_formatQty.format(b.qtySisa)} unit',
                  style: AppTypography.secondary,
                ),
                Text(
                  '${_formatTanggal.format(DateTime(tanggal.year, tanggal.month, tanggal.day))} · ${labelSisaHari(sisa)}',
                  key: Key('kedaluwarsa.status.${b.id}'),
                  style: AppTypography.secondary.copyWith(color: warna),
                ),
              ],
            ),
          ),
          IconButton(
            key: Key('kedaluwarsa.hapus.${b.id}'),
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Hapus batch',
            onPressed: () => unawaited(_hapus(context, ref)),
          ),
        ],
      ),
    );
  }

  Future<void> _hapus(BuildContext context, WidgetRef ref) async {
    final sesi = await ref.read(authSessionStoreProvider).muat();
    if (sesi == null) return;
    try {
      await ref.read(backendApiProvider).hapusBatchStok(accessToken: sesi.accessToken, batchId: item.batch.id);
      unawaited(ref.read(syncRepositoryProvider).jalankan());
    } catch (e) {
      if (context.mounted) showAppToast(context, message: 'Gagal menghapus: $e', variant: ToastVariant.danger);
    }
  }
}

class _DialogBatch extends StatefulWidget {
  const _DialogBatch({required this.outletId, required this.produk});

  final String outletId;
  final Map<String, String> produk;

  @override
  State<_DialogBatch> createState() => _DialogBatchState();
}

class _DialogBatchState extends State<_DialogBatch> {
  late String _produkId = widget.produk.keys.first;
  final _nomor = TextEditingController();
  final _qty = TextEditingController();
  final _ingatkan = TextEditingController(text: '30');
  DateTime? _tanggal;
  String? _galat;

  @override
  void dispose() {
    _nomor.dispose();
    _qty.dispose();
    _ingatkan.dispose();
    super.dispose();
  }

  Future<void> _pilihTanggal() async {
    final sekarang = DateTime.now();
    final hasil = await showDatePicker(
      context: context,
      initialDate: _tanggal ?? sekarang.add(const Duration(days: 30)),
      firstDate: DateTime(sekarang.year - 1),
      lastDate: DateTime(sekarang.year + 10),
    );
    if (hasil != null) setState(() => _tanggal = hasil);
  }

  void _simpan() {
    final qty = double.tryParse(_qty.text.replaceAll(',', '.'));
    final ingatkan = int.tryParse(_ingatkan.text);
    if (_tanggal == null) return setState(() => _galat = 'Pilih tanggal kedaluwarsa');
    if (qty == null || qty <= 0) return setState(() => _galat = 'Jumlah harus lebih dari 0');
    if (ingatkan == null || ingatkan < 0 || ingatkan > 365) return setState(() => _galat = 'Pengingat 0 sampai 365 hari');
    final t = _tanggal!;
    Navigator.pop(context, <String, dynamic>{
      'outlet_id': widget.outletId,
      'produk_id': _produkId,
      'nomor_batch': _nomor.text.trim().isEmpty ? null : _nomor.text.trim(),
      'tanggal_kedaluwarsa':
          '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}',
      'qty': qty,
      'ingatkan_hari': ingatkan,
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Catat batch'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              key: const Key('kedaluwarsa.form.produk'),
              initialValue: _produkId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Produk'),
              items: [for (final e in widget.produk.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: (v) => setState(() => _produkId = v ?? _produkId),
            ),
            TextField(
              key: const Key('kedaluwarsa.form.nomor'),
              controller: _nomor,
              decoration: const InputDecoration(labelText: 'Nomor batch (opsional)'),
            ),
            TextField(
              key: const Key('kedaluwarsa.form.qty'),
              controller: _qty,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Jumlah'),
            ),
            TextField(
              key: const Key('kedaluwarsa.form.ingatkan'),
              controller: _ingatkan,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Ingatkan berapa hari sebelumnya'),
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              key: const Key('kedaluwarsa.form.tanggal'),
              onPressed: _pilihTanggal,
              icon: const Icon(Icons.event),
              label: Text(_tanggal == null ? 'Pilih tanggal kedaluwarsa' : _formatTanggal.format(_tanggal!)),
            ),
            if (_galat != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Text(_galat!, style: AppTypography.secondary.copyWith(color: AppColors.dangerText)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
        FilledButton(key: const Key('kedaluwarsa.form.simpan'), onPressed: _simpan, child: const Text('Simpan')),
      ],
    );
  }
}
