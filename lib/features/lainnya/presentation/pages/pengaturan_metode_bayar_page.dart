import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

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
import '../../../transaksi/data/local/tables/metode_bayar_table.dart';
import '../../../transaksi/domain/label_tujuan.dart';
import '../../../transaksi/presentation/providers/transaksi_providers.dart';
import '../../../transaksi/presentation/providers/qris_providers.dart';
import '../../../../core/struk/qris_cache.dart';

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
      await ref.read(metodeBayarDaoProvider).ubahAktif(
            metode.id,
            aktif,
            now: DateTime.now().toUtc().millisecondsSinceEpoch,
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
    // Label tujuan (IMOGI no. 18) hanya bermakna untuk metode non-tunai.
    final bisaLabel = metode.tipe != MetodeBayarTipe.tunai;
    final labelController = TextEditingController(text: daftarLabelTujuan(metode.labelTujuan).join(', '));
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
            if (bisaLabel) ...[
              const SizedBox(height: AppSpacing.sm),
              TextField(
                key: const Key('pengaturanMetodeBayarForm.labelTujuan'),
                controller: labelController,
                decoration: const InputDecoration(
                  labelText: 'Label tujuan (pisahkan koma)',
                  helperText: 'Mis. GoPay, OVO, ShopeePay. Kasir memilih satu saat menerima pembayaran.',
                  helperMaxLines: 2,
                ),
              ),
            ],
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
    final label = bisaLabel ? normalisasiLabelTujuan(labelController.text) : (hasil: metode.labelTujuan, galat: null);
    if (label.galat != null) {
      if (context.mounted) showAppToast(context, message: label.galat!, variant: ToastVariant.warning);
      return;
    }
    final labelBerubah = bisaLabel && label.hasil != metode.labelTujuan;
    try {
      await ref.read(backendApiProvider).ubahMetodeBayar(
            accessToken: sesi.accessToken,
            metodeBayarId: metode.id,
            body: {
              'nama': namaController.text.trim(),
              'urutan': urutan,
              // Dikirim hanya bila berubah: label_tujuan sama-sama digate fitur label_pembayaran, dan
              // pengiriman ulang nilai lama tidak boleh memicu penolakan.
              if (labelBerubah) 'label_tujuan': label.hasil ?? '',
            },
          );
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      await ref.read(metodeBayarDaoProvider).ubahNamaUrutan(
            metode.id,
            nama: namaController.text.trim(),
            urutan: urutan,
            now: now,
          );
      if (labelBerubah) {
        await ref.read(metodeBayarDaoProvider).ubahLabelTujuan(metode.id, label.hasil, now: now);
      }
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

  Future<void> _ubahWajibReferensi(WidgetRef ref, BuildContext context, MetodeBayarRow metode, bool wajib) async {
    final sesi = await ref.read(authSessionStoreProvider).muat();
    if (sesi == null) return;
    try {
      await ref.read(backendApiProvider).ubahMetodeBayar(
            accessToken: sesi.accessToken,
            metodeBayarId: metode.id,
            body: {'wajib_referensi': wajib},
          );
      await ref.read(metodeBayarDaoProvider).ubahWajibReferensi(
            metode.id,
            wajib,
            now: DateTime.now().toUtc().millisecondsSinceEpoch,
          );
      unawaited(ref.read(syncRepositoryProvider).jalankan());
    } catch (e) {
      if (context.mounted) {
        showAppToast(context, message: 'Gagal mengubah: $e', variant: ToastVariant.danger);
      }
    }
  }

  Future<void> _editRekening(WidgetRef ref, BuildContext context, MetodeBayarRow metode) async {
    final bankC = TextEditingController(text: metode.rekeningBank ?? '');
    final nomorC = TextEditingController(text: metode.rekeningNomor ?? '');
    final namaC = TextEditingController(text: metode.rekeningNama ?? '');
    final disimpan = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rekening tujuan'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('pengaturanMetodeBayarForm.rekeningBank'),
              controller: bankC,
              decoration: const InputDecoration(labelText: 'Bank / e-wallet'),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              key: const Key('pengaturanMetodeBayarForm.rekeningNomor'),
              controller: nomorC,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Nomor rekening'),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              key: const Key('pengaturanMetodeBayarForm.rekeningNama'),
              controller: namaC,
              decoration: const InputDecoration(labelText: 'Atas nama'),
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
    String? bersih(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    try {
      await ref.read(backendApiProvider).ubahMetodeBayar(
            accessToken: sesi.accessToken,
            metodeBayarId: metode.id,
            body: {
              'rekening_bank': bersih(bankC),
              'rekening_nomor': bersih(nomorC),
              'rekening_nama': bersih(namaC),
            },
          );
      await ref.read(metodeBayarDaoProvider).ubahRekening(
            metode.id,
            bank: bersih(bankC),
            nomor: bersih(nomorC),
            nama: bersih(namaC),
            now: DateTime.now().toUtc().millisecondsSinceEpoch,
          );
      unawaited(ref.read(syncRepositoryProvider).jalankan());
      if (context.mounted) {
        showAppToast(context, message: 'Rekening tersimpan', variant: ToastVariant.success);
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
                          if (metode.rekeningNomor != null)
                            Text(
                              '${metode.rekeningBank ?? ''} ${metode.rekeningNomor} a.n. ${metode.rekeningNama ?? '-'}',
                              key: Key('pengaturanMetodeBayar.rekening.${metode.id}'),
                              style: AppTypography.secondary,
                            ),
                          if (metode.tipe == MetodeBayarTipe.kartu ||
                              metode.tipe == MetodeBayarTipe.transfer ||
                              metode.tipe == MetodeBayarTipe.ewallet)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('Wajib no. referensi', style: AppTypography.secondary),
                                Switch(
                                  key: Key('pengaturanMetodeBayar.wajibReferensi.${metode.id}'),
                                  value: metode.wajibReferensi,
                                  onChanged: online ? (v) => _ubahWajibReferensi(ref, context, metode, v) : null,
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                    if (metode.tipe == MetodeBayarTipe.qris)
                      FiturTerkunci(
                        kode: 'qris',
                        child: IconButton(
                          key: Key('pengaturanMetodeBayar.gambarQris.${metode.id}'),
                          icon: const Icon(Icons.qr_code_2),
                          tooltip: 'Gambar QRIS usaha',
                          onPressed: online ? () => showDialog<void>(context: context, builder: (_) => const _DialogGambarQris()) : null,
                        ),
                      ),
                    if (metode.tipe == MetodeBayarTipe.transfer || metode.tipe == MetodeBayarTipe.ewallet)
                      IconButton(
                        key: Key('pengaturanMetodeBayar.rekeningEdit.${metode.id}'),
                        icon: const Icon(Icons.account_balance_outlined),
                        tooltip: 'Rekening tujuan',
                        onPressed: online ? () => _editRekening(ref, context, metode) : null,
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

/// Kelola gambar QRIS statis usaha (IMOGI no. 10): lihat, unggah/ganti, atau hapus. Gambar disimpan di
/// server (digerbang fitur `qris`) dan di-cache lokal agar tetap tampil di layar bayar saat offline.
class _DialogGambarQris extends ConsumerStatefulWidget {
  const _DialogGambarQris();

  @override
  ConsumerState<_DialogGambarQris> createState() => _DialogGambarQrisState();
}

class _DialogGambarQrisState extends ConsumerState<_DialogGambarQris> {
  bool _sibuk = false;

  Future<void> _unggah() async {
    final sesi = await ref.read(authSessionStoreProvider).muat();
    if (sesi == null) return;
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 95);
    if (file == null) return;
    setState(() => _sibuk = true);
    try {
      final bytes = await file.readAsBytes();
      await ref.read(backendApiProvider).uploadQrisToko(accessToken: sesi.accessToken, bytes: bytes, namaFile: file.name);
      await QrisCache.simpan(bytes);
      ref.invalidate(qrisTokoProvider);
      if (mounted) showAppToast(context, message: 'Gambar QRIS tersimpan', variant: ToastVariant.success);
    } catch (e) {
      if (mounted) showAppToast(context, message: 'Gagal mengunggah: $e', variant: ToastVariant.danger);
    } finally {
      if (mounted) setState(() => _sibuk = false);
    }
  }

  Future<void> _hapus() async {
    final sesi = await ref.read(authSessionStoreProvider).muat();
    if (sesi == null) return;
    setState(() => _sibuk = true);
    try {
      await ref.read(backendApiProvider).deleteJson(accessToken: sesi.accessToken, path: '/toko/qris');
      await QrisCache.hapus();
      ref.invalidate(qrisTokoProvider);
      if (mounted) showAppToast(context, message: 'Gambar QRIS dihapus', variant: ToastVariant.success);
    } catch (e) {
      if (mounted) showAppToast(context, message: 'Gagal menghapus: $e', variant: ToastVariant.danger);
    } finally {
      if (mounted) setState(() => _sibuk = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final qris = ref.watch(qrisTokoProvider).value;
    return AlertDialog(
      key: const Key('gambarQris.dialog'),
      title: const Text('Gambar QRIS usaha'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (qris != null)
            Image.memory(qris, key: const Key('gambarQris.pratinjau'), width: 220, height: 220, fit: BoxFit.contain)
          else
            Text(
              'Belum ada gambar. Unggah gambar QRIS usaha (PNG/JPG, maks. 1 MB) yang diberikan bank atau penyedia '
              'QRIS Anda; kasir menampilkannya di layar bayar.',
              key: const Key('gambarQris.kosong'),
              style: AppTypography.secondary,
            ),
        ],
      ),
      actions: [
        if (qris != null)
          TextButton(key: const Key('gambarQris.hapus'), onPressed: _sibuk ? null : _hapus, child: const Text('Hapus')),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Tutup')),
        FilledButton(
          key: const Key('gambarQris.unggah'),
          onPressed: _sibuk ? null : _unggah,
          child: Text(_sibuk ? 'Memproses...' : (qris == null ? 'Unggah' : 'Ganti')),
        ),
      ],
    );
  }
}
