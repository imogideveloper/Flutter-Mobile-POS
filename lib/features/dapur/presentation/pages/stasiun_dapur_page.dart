import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/network/auth_session_store.dart';
import '../../../../core/network/dio_backend_api.dart';
import '../../../../core/providers/session_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../produk/presentation/providers/produk_providers.dart';

/// Stasiun dapur (IMOGI no. 35): mis. "Bar" dan "Dapur". Tiap kategori bisa ditautkan ke satu stasiun
/// (di form kategori) sehingga satu pesanan mencetak satu tiket per stasiun. Perlu koneksi untuk mengubah.
class StasiunDapurPage extends ConsumerWidget {
  const StasiunDapurPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final outletId = ref.watch(currentOutletIdProvider);
    final stasiun = ref.watch(stasiunDapurProvider(outletId));
    return Scaffold(
      appBar: AppBar(title: const Text('Stasiun dapur')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('stasiun.tambah'),
        onPressed: () => unawaited(_form(context, ref, outletId, null)),
        icon: const Icon(Icons.add),
        label: const Text('Tambah stasiun'),
      ),
      body: stasiun.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Gagal memuat: $e')),
        data: (items) {
          if (items.isEmpty) {
            return const EmptyState(
              icon: Icons.soup_kitchen_outlined,
              message:
                  'Belum ada stasiun. Tambahkan mis. "Bar" dan "Dapur", lalu pilih stasiun di tiap kategori.',
            );
          }
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            children: [
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var i = 0; i < items.length; i++)
                      Container(
                        key: Key('stasiun.baris.${items[i].id}'),
                        decoration: i < items.length - 1
                            ? const BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(
                                    color: AppColors.borderDefault,
                                  ),
                                ),
                              )
                            : null,
                        child: Material(
                          color: Colors.transparent,
                          child: ListTile(
                            title: Text(
                              items[i].nama,
                              style: AppTypography.bodyEmphasis,
                            ),
                            subtitle: Text(
                              'Kertas ${items[i].lebarKertasMm} mm',
                              style: AppTypography.secondary,
                            ),
                            onTap: () => unawaited(
                              _form(context, ref, outletId, items[i]),
                            ),
                            trailing: IconButton(
                              key: Key('stasiun.hapus.${items[i].id}'),
                              icon: const Icon(Icons.delete_outline),
                              tooltip: 'Hapus stasiun',
                              onPressed: () =>
                                  unawaited(_hapus(context, ref, items[i])),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _form(
    BuildContext context,
    WidgetRef ref,
    String outletId,
    StasiunDapurRow? ada,
  ) async {
    final hasil = await showDialog<({String nama, int lebar})>(
      context: context,
      builder: (_) => _DialogStasiun(awal: ada),
    );
    if (hasil == null || !context.mounted) return;
    final sesi = await ref.read(authSessionStoreProvider).muat();
    if (sesi == null) return;
    try {
      final body = {'nama': hasil.nama, 'lebar_kertas_mm': hasil.lebar};
      final api = ref.read(backendApiProvider);
      final respons =
          (ada == null
                  ? await api.postJson(
                      accessToken: sesi.accessToken,
                      path: '/outlets/$outletId/stasiun-dapur',
                      body: body,
                    )
                  : await api.patchJson(
                      accessToken: sesi.accessToken,
                      path: '/stasiun-dapur/${ada.id}',
                      body: body,
                    ))
              as Map<String, dynamic>;
      final now = DateTime.now().millisecondsSinceEpoch;
      await ref
          .read(produkDaoProvider)
          .upsertStasiunDapur(
            StasiunDapurCompanion.insert(
              id: respons['id'] as String,
              outletId: outletId,
              nama: respons['nama'] as String,
              printerAlamat: Value(respons['printer_alamat'] as String?),
              lebarKertasMm: Value((respons['lebar_kertas_mm'] as num).toInt()),
              aktif: Value(respons['aktif'] as bool? ?? true),
              createdAt: ada?.createdAt ?? now,
              updatedAt: now,
            ),
          );
    } catch (e) {
      if (context.mounted)
        showAppToast(
          context,
          message: 'Gagal menyimpan: $e',
          variant: ToastVariant.danger,
        );
    }
  }

  Future<void> _hapus(
    BuildContext context,
    WidgetRef ref,
    StasiunDapurRow s,
  ) async {
    final yakin = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Hapus stasiun ${s.nama}?'),
        content: const Text(
          'Kategori yang memakai stasiun ini kembali ke tiket umum.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            key: const Key('stasiun.hapus.ya'),
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
      await ref
          .read(backendApiProvider)
          .deleteJson(
            accessToken: sesi.accessToken,
            path: '/stasiun-dapur/${s.id}',
          );
      final now = DateTime.now().millisecondsSinceEpoch;
      await ref
          .read(produkDaoProvider)
          .upsertStasiunDapur(
            StasiunDapurCompanion.insert(
              id: s.id,
              outletId: s.outletId,
              nama: s.nama,
              createdAt: s.createdAt,
              updatedAt: now,
              deletedAt: Value(now),
            ),
          );
    } catch (e) {
      if (context.mounted)
        showAppToast(
          context,
          message: 'Gagal menghapus: $e',
          variant: ToastVariant.danger,
        );
    }
  }
}

class _DialogStasiun extends StatefulWidget {
  const _DialogStasiun({this.awal});

  final StasiunDapurRow? awal;

  @override
  State<_DialogStasiun> createState() => _DialogStasiunState();
}

class _DialogStasiunState extends State<_DialogStasiun> {
  late final _nama = TextEditingController(text: widget.awal?.nama ?? '');
  late int _lebar = widget.awal?.lebarKertasMm ?? 58;
  String? _galat;

  @override
  void dispose() {
    _nama.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.awal == null ? 'Tambah stasiun' : 'Ubah stasiun'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('stasiun.form.nama'),
            controller: _nama,
            maxLength: 50,
            decoration: const InputDecoration(
              labelText: 'Nama stasiun (mis. Bar, Dapur)',
            ),
          ),
          DropdownButtonFormField<int>(
            key: const Key('stasiun.form.lebar'),
            initialValue: _lebar,
            decoration: const InputDecoration(labelText: 'Lebar kertas'),
            items: const [
              DropdownMenuItem(value: 58, child: Text('58 mm')),
              DropdownMenuItem(value: 80, child: Text('80 mm')),
            ],
            onChanged: (v) => setState(() => _lebar = v ?? _lebar),
          ),
          if (_galat != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(
                _galat!,
                style: AppTypography.secondary.copyWith(
                  color: AppColors.dangerText,
                ),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton(
          key: const Key('stasiun.form.simpan'),
          onPressed: () {
            final nama = _nama.text.trim();
            if (nama.isEmpty)
              return setState(() => _galat = 'Nama stasiun wajib diisi');
            Navigator.pop(context, (nama: nama, lebar: _lebar));
          },
          child: const Text('Simpan'),
        ),
      ],
    );
  }
}
