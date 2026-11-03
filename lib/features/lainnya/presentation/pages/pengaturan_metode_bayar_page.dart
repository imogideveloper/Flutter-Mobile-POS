import 'dart:async';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/network/auth_session_store.dart';
import '../../../../core/network/dio_backend_api.dart';
import '../../../../core/network/sync_repository.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/fitur_terkunci.dart';
import '../../../../core/widgets/offline_notice_banner.dart';
import '../../../transaksi/presentation/providers/transaksi_providers.dart';

final _semuaMetodeBayarProvider = StreamProvider<List<MetodeBayarRow>>((ref) {
  return ref.watch(metodeBayarDaoProvider).watchSemuaMetodeBayar();
});

/// Pengaturan metode pembayaran (tahap 4 bagian B.3) - sama prinsip dgn
/// PengaturanOutletStrukPage: nama/urutan ditulis langsung ke backend
/// (digate 'label_pembayaran'), aktif/nonaktif JUGA ke backend tapi TIDAK
/// digate - lihat PATCH /metode-bayar/{id}. Cache lokal diperbarui
/// langsung setelah sukses, tidak menunggu sync penuh.
class PengaturanMetodeBayarPage extends ConsumerWidget {
  const PengaturanMetodeBayarPage({super.key});

  Future<void> _ubahAktif(WidgetRef ref, BuildContext context, MetodeBayarRow metode, bool aktif) async {
    final sesi = await ref.read(authSessionStoreProvider).muat();
    if (sesi == null) return;
    try {
      await ref.read(backendApiProvider).ubahMetodeBayar(
            accessToken: sesi.accessToken,
            metodeBayarId: metode.id,
            body: {'aktif': aktif},
          );
      await ref.read(metodeBayarDaoProvider).upsertMetodeBayar(
            MetodeBayarCompanion(id: Value(metode.id), aktif: Value(aktif)),
          );
      unawaited(ref.read(syncRepositoryProvider).jalankan());
    } catch (e) {
      if (context.mounted) {
        showAppToast(context, message: 'Gagal mengubah: $e', variant: ToastVariant.danger);
      }
    }
  }

  Future<void> _editNamaUrutan(WidgetRef ref, BuildContext context, MetodeBayarRow metode) async {
    final namaController = TextEditingController(text: metode.nama);
    final urutanController = TextEditingController(text: metode.urutan.toString());
    final disimpan = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ubah metode bayar'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('pengaturanMetodeBayarForm.nama'),
              controller: namaController,
              decoration: const InputDecoration(labelText: 'Nama/label'),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              key: const Key('pengaturanMetodeBayarForm.urutan'),
              controller: urutanController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Urutan'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Simpan')),
        ],
      ),
    );
    if (disimpan != true) return;
    if (!context.mounted) return;

    final sesi = await ref.read(authSessionStoreProvider).muat();
    if (sesi == null) return;
    final urutan = int.tryParse(urutanController.text) ?? metode.urutan;
    try {
      await ref.read(backendApiProvider).ubahMetodeBayar(
            accessToken: sesi.accessToken,
            metodeBayarId: metode.id,
            body: {'nama': namaController.text.trim(), 'urutan': urutan},
          );
      await ref.read(metodeBayarDaoProvider).upsertMetodeBayar(
            MetodeBayarCompanion(
              id: Value(metode.id),
              nama: Value(namaController.text.trim()),
              urutan: Value(urutan),
            ),
          );
      unawaited(ref.read(syncRepositoryProvider).jalankan());
      if (context.mounted) {
        showAppToast(context, message: 'Tersimpan', variant: ToastVariant.success);
      }
    } catch (e) {
      if (context.mounted) {
        showAppToast(context, message: 'Gagal menyimpan: $e', variant: ToastVariant.danger);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final daftarAsync = ref.watch(_semuaMetodeBayarProvider);
    final online = isOnlineSaat(ref);

    return Scaffold(
      appBar: AppBar(title: const Text('Metode pembayaran')),
      body: daftarAsync.when(
        data: (daftar) {
          if (daftar.isEmpty) {
            return const EmptyState(
              icon: Icons.payments_outlined,
              message: 'Belum ada metode pembayaran.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.xl),
            itemCount: daftar.length + 1,
            separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, index) {
              if (index == 0) return const OfflineNoticeBanner();
              final metode = daftar[index - 1];
              return AppCard(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(metode.nama, style: AppTypography.bodyEmphasis),
                          Text(metode.tipe.name, style: AppTypography.secondary),
                        ],
                      ),
                    ),
                    FiturTerkunci(
                      kode: 'label_pembayaran',
                      child: IconButton(
                        key: Key('pengaturanMetodeBayar.edit.${metode.id}'),
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: online ? () => _editNamaUrutan(ref, context, metode) : null,
                      ),
                    ),
                    Switch(
                      key: Key('pengaturanMetodeBayar.aktif.${metode.id}'),
                      value: metode.aktif,
                      onChanged: online ? (v) => _ubahAktif(ref, context, metode, v) : null,
                    ),
                  ],
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(child: Text('Gagal memuat: $error')),
      ),
    );
  }
}
