import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/auth_session_store.dart';
import '../../../../core/network/backend_exception.dart';
import '../../../../core/network/dio_backend_api.dart';
import '../../../../core/network/sync_repository.dart';
import '../../../../core/providers/izin_provider.dart';
import '../../../../core/providers/session_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../shift/presentation/providers/shift_providers.dart';

/// Outlet yang boleh dipakai pengguna ini (IMOGI no. 87), diambil dari server.
class OutletPilihan {
  const OutletPilihan({required this.id, required this.nama, required this.kode, this.alamat});

  final String id;
  final String nama;
  final String kode;
  final String? alamat;
}

final outletSayaProvider = FutureProvider.autoDispose<List<OutletPilihan>>((ref) async {
  final sesi = await ref.read(authSessionStoreProvider).muat();
  if (sesi == null) return const [];
  final data = await ref.read(backendApiProvider).getJson(accessToken: sesi.accessToken, path: '/outlets/saya');
  return [
    for (final o in (data as List).cast<Map<String, dynamic>>())
      OutletPilihan(
        id: o['id'] as String,
        nama: o['nama'] as String,
        kode: o['kode'] as String,
        alamat: o['alamat'] as String?,
      ),
  ];
});

/// Ganti outlet aktif: simpan ke sesi, arahkan provider, lalu tarik data outlet tujuan.
/// Transaksi outlet lama yang belum terkirim tetap membawa outlet-nya sendiri dan terkirim di sync berikutnya.
Future<void> gantiOutletAktif(WidgetRef ref, String outletId) async {
  await ref.read(authSessionStoreProvider).simpanOutletAktif(outletId);
  ref.read(currentOutletIdProvider.notifier).set(outletId);
  // Best-effort: kalau offline, data outlet baru terunduh pada sync berikutnya.
  unawaited(ref.read(syncRepositoryProvider).jalankan(outletId: outletId).then((_) {}, onError: (_) {}));
}

/// Kode outlet baru yang belum dipakai: OUT1, OUT2, ... (pemilik tidak perlu memikirkan kode).
String kodeOutletBaru(Iterable<String> kodeAda) {
  final ada = kodeAda.map((k) => k.toUpperCase()).toSet();
  var n = ada.length + 1;
  while (ada.contains('OUT$n')) {
    n++;
  }
  return 'OUT$n';
}

/// Tambah outlet baru (IMOGI no. 87). Hanya untuk peran dengan izin pengaturan.kelola; server tetap memeriksa izin,
/// fitur multi_outlet, dan kuota outlet langganan.
Future<void> tambahOutlet(BuildContext context, WidgetRef ref, List<OutletPilihan> ada) async {
  final nama = TextEditingController();
  final alamat = TextEditingController();
  final simpan = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Tambah outlet'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('tambahOutlet.nama'),
            controller: nama,
            decoration: const InputDecoration(labelText: 'Nama outlet', hintText: 'Contoh: Cabang Kemang'),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            key: const Key('tambahOutlet.alamat'),
            controller: alamat,
            decoration: const InputDecoration(labelText: 'Alamat (opsional)'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
        FilledButton(
          key: const Key('tambahOutlet.simpan'),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Simpan'),
        ),
      ],
    ),
  );
  if (simpan != true || !context.mounted) return;
  if (nama.text.trim().isEmpty) {
    showAppToast(context, message: 'Nama outlet wajib diisi', variant: ToastVariant.warning);
    return;
  }
  try {
    final sesi = await ref.read(authSessionStoreProvider).muat();
    if (sesi == null) throw const BackendException(message: 'Perangkat belum terhubung ke server');
    await ref.read(backendApiProvider).postJson(
      accessToken: sesi.accessToken,
      path: '/outlets',
      body: {
        'kode': kodeOutletBaru(ada.map((o) => o.kode)),
        'nama': nama.text.trim(),
        if (alamat.text.trim().isNotEmpty) 'alamat': alamat.text.trim(),
      },
    );
    ref.invalidate(outletSayaProvider);
    if (context.mounted) {
      showAppToast(context, message: 'Outlet ${nama.text.trim()} ditambahkan', variant: ToastVariant.success);
    }
  } on BackendException catch (e) {
    if (context.mounted) {
      showAppToast(
        context,
        message: e.tidakAdaKoneksi ? 'Butuh internet untuk menambah outlet.' : e.message,
        variant: ToastVariant.danger,
      );
    }
  }
}

class GantiOutletPage extends ConsumerWidget {
  const GantiOutletPage({super.key});

  Future<void> _pilih(BuildContext context, WidgetRef ref, OutletPilihan outlet) async {
    // Shift yang masih terbuka di outlet sekarang harus ditutup dulu, supaya kas laci tidak "tertinggal".
    final shift = await ref.read(shiftTerbukaProvider(ref.read(currentOutletIdProvider)).future);
    if (!context.mounted) return;
    if (shift != null) {
      showAppToast(
        context,
        message: 'Tutup shift di outlet ini dulu sebelum pindah outlet.',
        variant: ToastVariant.warning,
      );
      return;
    }
    final yakin = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Pindah ke ${outlet.nama}?'),
        content: const Text(
          'Produk, stok, dan pengaturan akan menampilkan data outlet ini. Transaksi yang belum terkirim tetap aman dan akan dikirim ke outlet asalnya.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(
            key: const Key('gantiOutlet.ya'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Pindah'),
          ),
        ],
      ),
    );
    if (yakin != true || !context.mounted) return;
    await gantiOutletAktif(ref, outlet.id);
    if (!context.mounted) return;
    showAppToast(context, message: 'Outlet aktif: ${outlet.nama}', variant: ToastVariant.success);
    unawaited(Navigator.of(context).maybePop());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aktifId = ref.watch(currentOutletIdProvider);
    final outlet = ref.watch(outletSayaProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Ganti outlet')),
      floatingActionButton: (ref.watch(izinSayaProvider).value?.contains('pengaturan.kelola') ?? false) && outlet.hasValue
          ? FloatingActionButton.extended(
              key: const Key('gantiOutlet.tambah'),
              onPressed: () => unawaited(tambahOutlet(context, ref, outlet.value!)),
              icon: const Icon(Icons.add_business_outlined),
              label: const Text('Tambah outlet'),
            )
          : null,
      body: outlet.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Gagal memuat outlet (perlu internet): $e')),
        data: (items) {
          if (items.isEmpty) {
            return const EmptyState(icon: Icons.storefront_outlined, message: 'Belum ada outlet yang bisa dipakai');
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
                        key: Key('gantiOutlet.baris.${items[i].id}'),
                        decoration: i < items.length - 1
                            ? const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.borderDefault)))
                            : null,
                        child: Material(
                          color: Colors.transparent,
                          child: ListTile(
                            title: Text(items[i].nama, style: AppTypography.bodyEmphasis),
                            subtitle: Text(
                              [items[i].kode, if (items[i].alamat != null) items[i].alamat!].join(' · '),
                              style: AppTypography.secondary,
                            ),
                            trailing: items[i].id == aktifId
                                ? const Icon(Icons.check_circle, color: AppColors.primaryDark)
                                : null,
                            onTap: items[i].id == aktifId ? null : () => unawaited(_pilih(context, ref, items[i])),
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
}
