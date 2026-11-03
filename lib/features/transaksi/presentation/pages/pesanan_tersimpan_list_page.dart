import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/auth/pin_approval.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/network/auth_session_store.dart';
import '../../../../core/network/backend_exception.dart';
import '../../../../core/network/dio_backend_api.dart';
import '../../../../core/providers/session_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/empty_state.dart';
import '../providers/harga_keranjang_provider.dart';
import '../providers/keranjang_provider.dart';
import '../providers/transaksi_providers.dart';

final _formatRupiah = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp', decimalDigits: 0);
final _formatWaktu = DateFormat('HH.mm, dd/MM');

/// F3.E.2 - daftar pesanan tersimpan (open bill) di outlet ini, SELALU
/// per-HP (lihat TransaksiRepository.watchPesananTersimpan). Tap = buka
/// kembali ke Keranjang (F3.E.3, harga dihitung ulang + peringatan kalau
/// beda); ikon hapus = batalkan draft.
class PesananTersimpanListPage extends ConsumerWidget {
  const PesananTersimpanListPage({super.key});

  Future<void> _bukaPesanan(BuildContext context, WidgetRef ref, TransaksiRow row) async {
    final items = await ref.read(transaksiRepositoryProvider).itemUntukResumePesanan(row.id);
    if (!context.mounted) return;
    if (items.isEmpty) {
      showAppToast(context, message: 'Pesanan ini sudah kosong', variant: ToastVariant.warning);
      return;
    }

    ref.read(keranjangProvider.notifier).muatDariPesananTersimpan(
          draftId: row.id,
          items: items,
          pelangganId: row.pelangganId,
          tipeOrderId: row.tipeOrderId,
          catatan: row.catatan,
        );

    // F3.E.3 - harga dihitung ULANG dari harga produk saat ini (promo/
    // harga bisa berubah sejak disimpan) - bandingkan dgn total yang
    // tersimpan saat draft dibuat, peringatkan kalau beda.
    final totalBaru = ref.read(hasilHargaKeranjangProvider).total;
    if (!context.mounted) return;
    if (totalBaru != row.total) {
      showAppToast(
        context,
        message: 'Harga berubah sejak disimpan: ${_formatRupiah.format(row.total)} -> ${_formatRupiah.format(totalBaru)}',
        variant: ToastVariant.info,
      );
    }
    context.push('/kasir/keranjang');
  }

  Future<void> _batalkan(BuildContext context, WidgetRef ref, TransaksiRow row) async {
    final alasanController = TextEditingController();
    final konfirmasi = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Batalkan pesanan #${row.nomorStruk}?'),
        content: TextField(
          controller: alasanController,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Alasan pembatalan'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Batal')),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(alasanController.text.trim().isNotEmpty),
            child: const Text('Batalkan pesanan'),
          ),
        ],
      ),
    );
    if (konfirmasi != true) return;
    final alasan = alasanController.text.trim();

    // Temuan#2 (rapikan F3.E) - approval PIN owner/manajer WAJIB kalau
    // total pesanan > 0 (default batas server, lihat
    // app/core/config.py::batas_approval_batal_pesanan) DAN kasir tidak
    // punya izin transaksi.batal_pesanan sendiri - mintaOtorisasi() sudah
    // menangani "sudah berizin -> lolos tanpa nanya PIN" secara otomatis.
    String? disetujuiOleh;
    if (row.total > 0) {
      if (!context.mounted) return;
      disetujuiOleh = await mintaOtorisasi(
        context: context,
        ref: ref,
        kodeIzin: 'transaksi.batal_pesanan',
        aksiLabel: 'Batalkan pesanan #${row.nomorStruk}',
      );
      if (disetujuiOleh == null) {
        if (context.mounted) {
          showAppToast(context, message: 'Pembatalan dibatalkan / PIN tidak valid', variant: ToastVariant.warning);
        }
        return;
      }
    }

    final idAntrean = await ref.read(transaksiRepositoryProvider).batalkanPesanan(
          row.id,
          alasan,
          disetujuiOleh: disetujuiOleh,
          penggunaId: ref.read(currentPenggunaIdProvider),
        );

    // "Online langsung" - coba kirim SEKARANG; kalau gagal (offline/server
    // error), baris antrean lokal TETAP ada (disinkronPada null) dan
    // otomatis ikut terkirim lewat SyncRepository di sync berikutnya
    // ("offline lewat push") - tidak pernah hilang.
    try {
      final sesi = await ref.read(authSessionStoreProvider).muat();
      if (sesi != null) {
        await ref.read(backendApiProvider).batalkanPesananTersimpan(
              accessToken: sesi.accessToken,
              pesananId: idAntrean,
              body: {
                'alasan': alasan,
                'disetujui_oleh': disetujuiOleh,
              },
            );
        await ref.read(transaksiRepositoryProvider).tandaiPembatalanPesananSudahSync(idAntrean);
      }
    } on BackendException {
      // Offline/gagal - sudah aman di antrean lokal, tidak perlu
      // diberitahu sbg error ke kasir (bukan bagian dari alur utama).
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final daftarAsync = ref.watch(pesananTersimpanProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Pesanan tersimpan')),
      body: daftarAsync.when(
        data: (daftar) {
          if (daftar.isEmpty) {
            return const EmptyState(
              icon: Icons.bookmark_border,
              message: 'Belum ada pesanan tersimpan.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.xl),
            itemCount: daftar.length,
            separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, index) {
              final row = daftar[index];
              final waktu = DateTime.fromMillisecondsSinceEpoch(row.tanggal, isUtc: true).toLocal();
              return AppCard(
                onTap: () => _bukaPesanan(context, ref, row),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('#${row.nomorStruk}', style: AppTypography.bodyEmphasis),
                          Text(_formatWaktu.format(waktu), style: AppTypography.secondary),
                        ],
                      ),
                    ),
                    Text(_formatRupiah.format(row.total), style: AppTypography.bodyEmphasis),
                    IconButton(
                      key: Key('pesananTersimpan.batalkan.${row.id}'),
                      icon: const Icon(Icons.close, color: AppColors.dangerTextStrong),
                      onPressed: () => _batalkan(context, ref, row),
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
