import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/database/app_database.dart' show ProdukKemasanCompanion, ProdukKemasanRow;
import '../../../../core/network/auth_session_store.dart';
import '../../../../core/network/dio_backend_api.dart';
import '../../../../core/providers/session_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/fitur_terkunci.dart';
import '../providers/produk_providers.dart';

final _rupiah = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp', decimalDigits: 0);

String _labelIsi(double isi) => isi == isi.roundToDouble() ? isi.toStringAsFixed(0) : isi.toString();

/// Kemasan jual produk (IMOGI no. 43): mis. Dus = 12 satuan dengan harga sendiri. Stok tetap di satuan
/// dasar produk. Perlu koneksi untuk mengubah; hasilnya langsung dicatat ke cache lokal.
class KemasanProdukSection extends ConsumerWidget {
  const KemasanProdukSection({super.key, required this.produkId});

  final String produkId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FiturTerkunci(
      kode: 'pack_units',
      child: Consumer(
        builder: (context, ref, _) {
          final tokoId = ref.watch(currentTokoIdProvider);
          final daftar = ref.watch(kemasanPerProdukProvider(tokoId))[produkId] ?? const <ProdukKemasanRow>[];
          return AppCard(
            key: const Key('kemasan.seksi'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Kemasan jual', style: AppTypography.cardTitle),
                const SizedBox(height: 2),
                Text(
                  'Jual per dus/pak dengan harga sendiri. Stok tetap dihitung per satuan dasar.',
                  style: AppTypography.secondary,
                ),
                const SizedBox(height: AppSpacing.md),
                if (daftar.isEmpty)
                  Text('Belum ada kemasan.', style: AppTypography.secondary)
                else
                  for (final k in daftar)
                    ListTile(
                      key: Key('kemasan.baris.${k.id}'),
                      contentPadding: EdgeInsets.zero,
                      title: Text(k.nama, style: AppTypography.bodyEmphasis),
                      subtitle: Text('Isi ${_labelIsi(k.isi)} satuan · ${_rupiah.format(k.harga)}'),
                      onTap: () => unawaited(_form(context, ref, k)),
                      trailing: IconButton(
                        key: Key('kemasan.hapus.${k.id}'),
                        icon: const Icon(Icons.delete_outline),
                        tooltip: 'Hapus kemasan',
                        onPressed: () => unawaited(_hapus(context, ref, k)),
                      ),
                    ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const Key('kemasan.tambah'),
                    onPressed: () => unawaited(_form(context, ref, null)),
                    icon: const Icon(Icons.add),
                    label: const Text('Tambah kemasan'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _form(BuildContext context, WidgetRef ref, ProdukKemasanRow? ada) async {
    final hasil = await showDialog<({String nama, double isi, int harga})>(
      context: context,
      builder: (_) => _DialogKemasan(awal: ada),
    );
    if (hasil == null || !context.mounted) return;
    final sesi = await ref.read(authSessionStoreProvider).muat();
    if (sesi == null) return;
    try {
      final body = {'nama': hasil.nama, 'isi': hasil.isi, 'harga': hasil.harga};
      final api = ref.read(backendApiProvider);
      final respons = (ada == null
          ? await api.postJson(accessToken: sesi.accessToken, path: '/produk/$produkId/kemasan', body: body)
          : await api.patchJson(accessToken: sesi.accessToken, path: '/kemasan/${ada.id}', body: body))
          as Map<String, dynamic>;
      final now = DateTime.now().millisecondsSinceEpoch;
      await ref.read(produkDaoProvider).upsertKemasan(
            ProdukKemasanCompanion.insert(
              id: respons['id'] as String,
              tokoId: ref.read(currentTokoIdProvider),
              produkId: produkId,
              nama: respons['nama'] as String,
              isi: double.parse('${respons['isi']}'),
              harga: double.parse('${respons['harga']}').round(),
              createdAt: ada?.createdAt ?? now,
              updatedAt: now,
            ),
          );
    } catch (e) {
      if (context.mounted) {
        showAppToast(context, message: 'Gagal menyimpan: $e', variant: ToastVariant.danger);
      }
    }
  }

  Future<void> _hapus(BuildContext context, WidgetRef ref, ProdukKemasanRow k) async {
    final yakin = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Hapus kemasan ${k.nama}?'),
        content: const Text('Transaksi lama tetap tercatat. Kemasan tidak muncul lagi di kasir.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(
            key: const Key('kemasan.hapus.ya'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (yakin != true || !context.mounted) return;
    final sesi = await ref.read(authSessionStoreProvider).muat();
    if (sesi == null) return;
    try {
      await ref.read(backendApiProvider).deleteJson(accessToken: sesi.accessToken, path: '/kemasan/${k.id}');
      final now = DateTime.now().millisecondsSinceEpoch;
      await ref.read(produkDaoProvider).upsertKemasan(
            ProdukKemasanCompanion.insert(
              id: k.id,
              tokoId: k.tokoId,
              produkId: k.produkId,
              nama: k.nama,
              isi: k.isi,
              harga: k.harga,
              createdAt: k.createdAt,
              updatedAt: now,
              deletedAt: Value(now),
            ),
          );
    } catch (e) {
      if (context.mounted) {
        showAppToast(context, message: 'Gagal menghapus: $e', variant: ToastVariant.danger);
      }
    }
  }
}

class _DialogKemasan extends StatefulWidget {
  const _DialogKemasan({this.awal});

  final ProdukKemasanRow? awal;

  @override
  State<_DialogKemasan> createState() => _DialogKemasanState();
}

class _DialogKemasanState extends State<_DialogKemasan> {
  late final _nama = TextEditingController(text: widget.awal?.nama ?? '');
  late final _isi = TextEditingController(text: widget.awal == null ? '' : _labelIsi(widget.awal!.isi));
  late final _harga = TextEditingController(text: widget.awal == null ? '' : '${widget.awal!.harga}');
  String? _galat;

  @override
  void dispose() {
    _nama.dispose();
    _isi.dispose();
    _harga.dispose();
    super.dispose();
  }

  void _simpan() {
    final nama = _nama.text.trim();
    final isi = double.tryParse(_isi.text.trim().replaceAll(',', '.'));
    final harga = int.tryParse(_harga.text.trim());
    if (nama.isEmpty) return setState(() => _galat = 'Nama kemasan wajib diisi');
    if (isi == null || isi <= 1) return setState(() => _galat = 'Isi harus lebih dari 1');
    if (harga == null || harga < 0) return setState(() => _galat = 'Harga kemasan wajib diisi');
    Navigator.pop(context, (nama: nama, isi: isi, harga: harga));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.awal == null ? 'Tambah kemasan' : 'Ubah kemasan'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('kemasan.form.nama'),
              controller: _nama,
              maxLength: 50,
              decoration: const InputDecoration(labelText: 'Nama kemasan (mis. Dus, Pak)'),
            ),
            TextField(
              key: const Key('kemasan.form.isi'),
              controller: _isi,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Isi (jumlah satuan dasar per kemasan)'),
            ),
            TextField(
              key: const Key('kemasan.form.harga'),
              controller: _harga,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Harga per kemasan (Rp)'),
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
        FilledButton(key: const Key('kemasan.form.simpan'), onPressed: _simpan, child: const Text('Simpan')),
      ],
    );
  }
}
