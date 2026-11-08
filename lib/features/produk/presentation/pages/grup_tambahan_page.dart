import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/network/auth_session_store.dart';
import '../../../../core/network/dio_backend_api.dart';
import '../../../../core/network/sync_mapping.dart';
import '../../../../core/providers/session_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../domain/grup_tambahan.dart';
import '../providers/produk_providers.dart';

final _rupiah = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp', decimalDigits: 0);

final grupTambahanKelolaProvider = StreamProvider<List<GrupTambahan>>((ref) {
  return ref.watch(produkDaoProvider).watchGrupKelola();
});

String aturanGrup(GrupTambahan g) {
  if (g.pilihTunggal) return g.wajib ? 'Wajib pilih 1' : 'Pilih 1 (opsional)';
  final maks = g.maksPilih == 0 ? '' : ', maks ${g.maksPilih}';
  return g.wajib ? 'Wajib minimal ${g.minPilih}$maks' : 'Opsional$maks';
}

/// Kelola varian & tambahan produk (dokumen IMOGI no. 42): grup seperti
/// "Ukuran", "Level gula", "Topping" beserta opsinya. Online-direct: disimpan
/// ke backend lebih dulu, cache lokal menyusul.
class GrupTambahanPage extends ConsumerWidget {
  const GrupTambahanPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final grup = ref.watch(grupTambahanKelolaProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Varian & tambahan')),
      floatingActionButton: FloatingActionButton(
        key: const Key('grup_tambahan.tambah'),
        tooltip: 'Tambah grup',
        onPressed: () => _dialogGrup(context, ref),
        child: const Icon(Icons.add),
      ),
      body: grup.when(
        data: (items) {
          if (items.isEmpty) {
            return const EmptyState(
              icon: Icons.tune,
              message: 'Belum ada varian atau tambahan.\nBuat grup mis. Ukuran, Level gula, atau Topping.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.xl),
            itemCount: items.length,
            separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, i) {
              final g = items[i];
              return AppCard(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => GrupTambahanDetailPage(grupId: g.id)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(g.nama, style: AppTypography.bodyEmphasis),
                          const SizedBox(height: 2),
                          Text('${aturanGrup(g)} · ${g.opsi.length} opsi', style: AppTypography.secondary),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Gagal memuat: $e')),
      ),
    );
  }
}

class GrupTambahanDetailPage extends ConsumerWidget {
  const GrupTambahanDetailPage({super.key, required this.grupId});

  final String grupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final semua = ref.watch(grupTambahanKelolaProvider).value ?? const <GrupTambahan>[];
    final g = semua.where((x) => x.id == grupId).firstOrNull;
    if (g == null) {
      return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.tune, message: 'Grup tidak ditemukan'));
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(g.nama),
        actions: [
          IconButton(
            key: const Key('grup_tambahan.ubah'),
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Ubah grup',
            onPressed: () => _dialogGrup(context, ref, grup: g),
          ),
          IconButton(
            key: const Key('grup_tambahan.hapus'),
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Hapus grup',
            onPressed: () => _hapusGrup(context, ref, g),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        key: const Key('grup_tambahan.tambah_opsi'),
        tooltip: 'Tambah opsi',
        onPressed: () => _dialogOpsi(context, ref, g),
        child: const Icon(Icons.add),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        children: [
          Text(aturanGrup(g), style: AppTypography.secondary),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            key: const Key('grup_tambahan.produk'),
            icon: const Icon(Icons.inventory_2_outlined),
            label: const Text('Produk yang memakai grup ini'),
            onPressed: () => _dialogProduk(context, ref, g),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (g.opsi.isEmpty)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.xl),
              child: Text('Belum ada opsi. Tambah mis. Regular, Large.'),
            ),
          for (final o in g.opsi)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: AppCard(
                onTap: () => _dialogOpsi(context, ref, g, opsi: o),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        o.nama,
                        style: AppTypography.bodyEmphasis.copyWith(color: o.aktif ? null : AppColors.textSecondary),
                      ),
                    ),
                    if (!o.aktif) const Text('Nonaktif  ', style: TextStyle(color: AppColors.textSecondary)),
                    Text(o.harga == 0 ? 'Gratis' : '+${_rupiah.format(o.harga)}'),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ aksi --

Future<String?> _token(BuildContext context, WidgetRef ref) async {
  final sesi = await ref.read(authSessionStoreProvider).muat();
  if (sesi == null && context.mounted) {
    showAppToast(context, message: 'Device belum pairing ke backend.', variant: ToastVariant.warning);
  }
  return sesi?.accessToken;
}

Future<void> _dialogGrup(BuildContext context, WidgetRef ref, {GrupTambahan? grup}) async {
  final nama = TextEditingController(text: grup?.nama ?? '');
  final min = TextEditingController(text: '${grup?.minPilih ?? 0}');
  final maks = TextEditingController(text: '${grup?.maksPilih ?? 1}');
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(grup == null ? 'Grup baru' : 'Ubah grup'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(key: const Key('grup.nama'), controller: nama, decoration: const InputDecoration(labelText: 'Nama grup (mis. Ukuran)')),
          TextField(
            key: const Key('grup.min'),
            controller: min,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Minimal pilih (0 = opsional)'),
          ),
          TextField(
            key: const Key('grup.maks'),
            controller: maks,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Maksimal pilih (1 = pilih satu)'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Batal')),
        FilledButton(key: const Key('grup.simpan'), onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Simpan')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  final minNilai = int.tryParse(min.text) ?? 0;
  final maksNilai = int.tryParse(maks.text) ?? 1;
  if (nama.text.trim().isEmpty) {
    showAppToast(context, message: 'Nama grup wajib diisi', variant: ToastVariant.warning);
    return;
  }
  if (maksNilai < 1 || minNilai > maksNilai) {
    showAppToast(context, message: 'Maksimal minimal 1 dan tidak boleh lebih kecil dari minimal', variant: ToastVariant.warning);
    return;
  }
  final token = await _token(context, ref);
  if (token == null || !context.mounted) return;
  try {
    final body = {'nama': nama.text.trim(), 'min_pilih': minNilai, 'maks_pilih': maksNilai};
    final api = ref.read(backendApiProvider);
    final hasil = (grup == null
        ? await api.postJson(accessToken: token, path: '/grup-modifier', body: body)
        : await api.patchJson(accessToken: token, path: '/grup-modifier/${grup.id}', body: body)) as Map<String, dynamic>;
    final now = DateTime.now().millisecondsSinceEpoch;
    await ref.read(produkDaoProvider).upsertGrupModifier(GrupModifierCompanion.insert(
          id: hasil['id'] as String,
          tokoId: ref.read(currentTokoIdProvider),
          nama: hasil['nama'] as String,
          minPilih: Value(hasil['min_pilih'] as int),
          maksPilih: Value(hasil['maks_pilih'] as int),
          createdAt: now,
          updatedAt: now,
        ));
  } catch (e) {
    if (context.mounted) showAppToast(context, message: 'Gagal menyimpan: $e', variant: ToastVariant.danger);
  }
}

Future<void> _hapusGrup(BuildContext context, WidgetRef ref, GrupTambahan g) async {
  final ya = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Hapus grup?'),
      content: Text('"${g.nama}" dan opsinya tidak akan muncul lagi di kasir. Transaksi lama tidak berubah.'),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Batal')),
        FilledButton(key: const Key('grup.hapus_ya'), onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Hapus')),
      ],
    ),
  );
  if (ya != true || !context.mounted) return;
  final token = await _token(context, ref);
  if (token == null || !context.mounted) return;
  try {
    await ref.read(backendApiProvider).deleteJson(accessToken: token, path: '/grup-modifier/${g.id}');
    await ref.read(produkDaoProvider).hapusGrupLokal(g.id);
    if (context.mounted) Navigator.of(context).pop();
  } catch (e) {
    if (context.mounted) showAppToast(context, message: 'Gagal menghapus: $e', variant: ToastVariant.danger);
  }
}

Future<void> _dialogOpsi(BuildContext context, WidgetRef ref, GrupTambahan g, {OpsiTambahan? opsi}) async {
  final nama = TextEditingController(text: opsi?.nama ?? '');
  final harga = TextEditingController(text: '${opsi?.harga ?? 0}');
  var aktif = opsi?.aktif ?? true;
  final aksi = await showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: Text(opsi == null ? 'Opsi baru' : 'Ubah opsi'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(key: const Key('opsi.nama'), controller: nama, decoration: const InputDecoration(labelText: 'Nama opsi (mis. Large)')),
            TextField(
              key: const Key('opsi.harga'),
              controller: harga,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Harga tambahan (Rp, 0 = gratis)'),
            ),
            if (opsi != null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Aktif'),
                value: aktif,
                onChanged: (v) => setS(() => aktif = v),
              ),
          ],
        ),
        actions: [
          if (opsi != null)
            TextButton(key: const Key('opsi.hapus'), onPressed: () => Navigator.of(ctx).pop('hapus'), child: const Text('Hapus')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Batal')),
          FilledButton(key: const Key('opsi.simpan'), onPressed: () => Navigator.of(ctx).pop('simpan'), child: const Text('Simpan')),
        ],
      ),
    ),
  );
  if (aksi == null || !context.mounted) return;
  final token = await _token(context, ref);
  if (token == null || !context.mounted) return;
  final dao = ref.read(produkDaoProvider);
  final api = ref.read(backendApiProvider);
  try {
    if (aksi == 'hapus') {
      await api.deleteJson(accessToken: token, path: '/grup-modifier/${g.id}/modifier/${opsi!.id}');
      await dao.hapusModifierLokal(opsi.id);
      return;
    }
    if (nama.text.trim().isEmpty) {
      showAppToast(context, message: 'Nama opsi wajib diisi', variant: ToastVariant.warning);
      return;
    }
    final body = <String, dynamic>{
      'nama': nama.text.trim(),
      'harga_tambahan': int.tryParse(harga.text) ?? 0,
      if (opsi != null) 'aktif': aktif,
    };
    final hasil = (opsi == null
        ? await api.postJson(accessToken: token, path: '/grup-modifier/${g.id}/modifier', body: {...body, 'urutan': g.opsi.length})
        : await api.patchJson(accessToken: token, path: '/grup-modifier/${g.id}/modifier/${opsi.id}', body: body)) as Map<String, dynamic>;
    final now = DateTime.now().millisecondsSinceEpoch;
    await dao.upsertModifier(ModifierCompanion.insert(
      id: hasil['id'] as String,
      grupModifierId: g.id,
      nama: hasil['nama'] as String,
      hargaTambahan: Value(uangDariBackend(hasil['harga_tambahan'].toString())),
      urutan: Value(hasil['urutan'] as int),
      aktif: Value(hasil['aktif'] as bool),
      createdAt: now,
      updatedAt: now,
    ));
  } catch (e) {
    if (context.mounted) showAppToast(context, message: 'Gagal menyimpan: $e', variant: ToastVariant.danger);
  }
}

Future<void> _dialogProduk(BuildContext context, WidgetRef ref, GrupTambahan g) async {
  final dao = ref.read(produkDaoProvider);
  final semuaProduk = await ref.read(produkSemuaProvider.future);
  final terpilih = await dao.produkIdUntukGrup(g.id);
  if (!context.mounted) return;
  final hasil = await showDialog<Set<String>>(
    context: context,
    builder: (ctx) {
      final pilih = {...terpilih};
      return StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text('Produk untuk ${g.nama}'),
          content: SizedBox(
            width: double.maxFinite,
            child: semuaProduk.isEmpty
                ? const Text('Belum ada produk.')
                : ListView(
                    shrinkWrap: true,
                    children: [
                      for (final p in semuaProduk)
                        CheckboxListTile(
                          key: Key('grup.produk.${p.id}'),
                          contentPadding: EdgeInsets.zero,
                          title: Text(p.nama),
                          value: pilih.contains(p.id),
                          onChanged: (v) => setS(() => v == true ? pilih.add(p.id) : pilih.remove(p.id)),
                        ),
                    ],
                  ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Batal')),
            FilledButton(key: const Key('grup.produk.simpan'), onPressed: () => Navigator.of(ctx).pop(pilih), child: const Text('Simpan')),
          ],
        ),
      );
    },
  );
  if (hasil == null || !context.mounted) return;
  final token = await _token(context, ref);
  if (token == null || !context.mounted) return;
  try {
    await ref.read(backendApiProvider).putJsonIds(
          accessToken: token,
          path: '/grup-modifier/${g.id}/produk',
          ids: hasil.toList(),
        );
    await dao.setProdukUntukGrupLokal(g.id, hasil);
    if (context.mounted) showAppToast(context, message: 'Produk diperbarui', variant: ToastVariant.success);
  } catch (e) {
    if (context.mounted) showAppToast(context, message: 'Gagal menyimpan: $e', variant: ToastVariant.danger);
  }
}
