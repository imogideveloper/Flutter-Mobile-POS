import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
