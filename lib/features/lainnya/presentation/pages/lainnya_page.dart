import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/network/backend_exception.dart';
import '../../../../core/network/sync_repository.dart';
import '../../../../core/providers/izin_provider.dart';
import '../../../../core/providers/session_provider.dart';
import '../../../../core/providers/toko_profile_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/avatar_initial.dart';
import '../../../../core/widgets/fitur_terkunci.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../../core/widgets/settings_menu_row.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../fitur/presentation/providers/feature_gate_provider.dart';
import '../../../../core/printer/pengaturan_printer_providers.dart';
import '../../../pelanggan/presentation/providers/pelanggan_providers.dart';
import '../../../shift/presentation/providers/shift_providers.dart';
import '../../../stok/presentation/providers/stok_providers.dart';
import '../../../transaksi/presentation/providers/transaksi_providers.dart';

final _formatWaktu = DateFormat('HH.mm');

/// Sesuai mockup "Lainnya": kartu profil toko, kartu status sync, 3 grup
/// menu (Operasional/Toko/Akun) - SEMUA baris sudah tersambung ke halaman
/// nyata (termasuk F3.F Paket langganan, item terakhir yang masih stub).
/// Tombol "Sync" sudah memanggil SyncRepository sungguhan (push transaksi
/// + pull data master) - lihat core/network/sync_repository.dart.
class LainnyaPage extends ConsumerWidget {
  const LainnyaPage({super.key});

  Future<void> _sinkronManual(BuildContext context, WidgetRef ref) async {
    showAppToast(
      context,
      message: 'Sinkronisasi dimulai...',
      variant: ToastVariant.info,
    );
    try {
      final hasil = await ref.read(syncRepositoryProvider).jalankan();
      // Status gating paket (FeatureGate) baru diperbarui lewat pull -
      // invalidate manual krn providernya FutureProvider satu-shot (bukan
      // reaktif otomatis, lihat catatan di feature_gate_provider.dart).
      ref.invalidate(featureGateProvider);
      if (!context.mounted) return;
      showAppToast(
        context,
        message:
            '${hasil.transaksiTerkirim} transaksi terkirim, '
            '${hasil.jumlahDiterimaPull} data master diperbarui'
            '${hasil.transaksiDitolak > 0 ? ' (${hasil.transaksiDitolak} ditolak)' : ''}',
        variant: hasil.transaksiDitolak > 0
            ? ToastVariant.warning
            : ToastVariant.success,
      );
    } on BackendException catch (e) {
      if (context.mounted) {
        showAppToast(
          context,
          message: 'Sync gagal: ${e.message}',
          variant: ToastVariant.danger,
        );
      }
    } finally {
      // Penghitung "menunggu sync" adalah FutureProvider satu-shot: tanpa ini angkanya
      // tertinggal di nilai lama walau server sudah menerima transaksinya.
      ref.invalidate(transaksiBelumSyncCountProvider);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokoId = ref.watch(currentTokoIdProvider);
    final outletId = ref.watch(currentOutletIdProvider);
    final profilAsync = ref.watch(tokoProfileProvider);
    final penggunaId = ref.watch(currentPenggunaIdProvider);
    final penggunaListAsync = ref.watch(penggunaAktifProvider(tokoId));
    final roleListAsync = ref.watch(roleBawaanProvider);
    final belumSyncAsync = ref.watch(transaksiBelumSyncCountProvider);
    final shiftAsync = ref.watch(shiftTerbukaProvider(outletId));
    final pelangganAsync = ref.watch(pelangganAktifProvider);
    final stokAsync = ref.watch(stokOutletProvider(outletId));

    final namaToko = profilAsync.value?.namaToko ?? 'Toko saya';
    final penggunaSaatIni = penggunaListAsync.value
        ?.where((p) => p.id == penggunaId)
        .firstOrNull;
    final roleSaatIni = roleListAsync.value
        ?.where((r) => r.id == penggunaSaatIni?.roleId)
        .firstOrNull;
    final subtitlProfil = [
      if (penggunaSaatIni != null) penggunaSaatIni.nama,
      if (roleSaatIni != null) roleSaatIni.nama,
      'Outlet Pusat',
    ].join(' · ');
    final inisialToko = namaToko
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0])
        .take(2)
        .join()
        .toUpperCase();

    final jumlahBelumSync = belumSyncAsync.value ?? 0;
    final jumlahPelanggan = pelangganAsync.value?.length ?? 0;
    final jumlahMenipis =
        stokAsync.value?.where((s) => s.stokMenipis).length ?? 0;
    final jumlahKaryawan = penggunaListAsync.value?.length ?? 0;
    final shift = shiftAsync.value;

    // Menu yang bukan hak role disembunyikan (kasir tidak melihat Pengguna/Pengaturan/Stok).
    // Selama izin belum termuat, semua menu terbatas disembunyikan (aman secara bawaan).
    final izinSaya = ref.watch(izinSayaProvider).value ?? const <String>{};
    Widget bila(String kodeIzin, Widget row) =>
        izinSaya.contains(kodeIzin) ? row : const SizedBox.shrink();

    return Scaffold(
      appBar: AppBar(title: const Text('Lainnya')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppCard(
              child: Row(
                children: [
                  AvatarInitial(
                    text: inisialToko.isEmpty ? '?' : inisialToko,
                    background: AppColors.brownBg,
                    foreground: AppColors.brownText,
                    size: 48,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(namaToko, style: AppTypography.cardTitle),
                        Text(subtitlProfil, style: AppTypography.secondary),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primaryTint,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'Gratis',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primaryDark,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            AppCard(
              child: Row(
                children: [
                  const Icon(
                    Icons.sync,
                    color: AppColors.warningTextStrong,
                    size: 20,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          jumlahBelumSync == 0
                              ? 'Semua transaksi tersinkron'
                              : '$jumlahBelumSync transaksi menunggu sync',
                          style: AppTypography.bodyEmphasis,
                        ),
                        Text(
                          'Ketuk Sync utk kirim/ambil data terbaru',
                          style: AppTypography.secondary,
                        ),
                      ],
                    ),
                  ),
                  OutlinedButton(
                    onPressed: () => _sinkronManual(context, ref),
                    child: const Text('Sync'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            const SectionHeader(label: 'Operasional'),
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  bila(
                    'shift.buka_tutup',
                    SettingsMenuRow(
                      label: 'Tutup shift',
                      value: shift == null
                          ? 'Shift tutup'
                          : 'sejak ${_formatWaktu.format(DateTime.fromMillisecondsSinceEpoch(shift.dibukaPada, isUtc: true).toLocal())}',
                      onTap: () => context.push('/shift'),
                    ),
                  ),
                  bila(
                    'shift.buka_tutup',
                    SettingsMenuRow(
                      label: 'Kas keluar / masuk',
                      value: 'Lihat shift',
                      onTap: () => context.push('/shift'),
                    ),
                  ),
                  Consumer(
                    builder: (context, ref, _) {
                      final punya =
                          ref
                              .watch(featureGateProvider)
                              .value
                              ?.has('status_pesanan') ??
                          false;
                      if (!punya) return const SizedBox.shrink();
                      return SettingsMenuRow(
                        label: 'Status pesanan',
                        value: 'Pantau',
                        onTap: () => context.push('/status-pesanan'),
                      );
                    },
                  ),
                  bila(
                    'pelanggan.kelola',
                    SettingsMenuRow(
                      label: 'Pelanggan',
                      value: '$jumlahPelanggan',
                      onTap: () => context.push('/pelanggan'),
                    ),
                  ),
                  bila(
                    'stok.kelola',
                    SettingsMenuRow(
                      label: 'Stok',
                      value: jumlahMenipis == 0
                          ? 'Aman'
                          : '$jumlahMenipis menipis',
                      onTap: () => context.push('/stok'),
                      showDivider: false,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            const SectionHeader(label: 'Toko'),
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  bila(
                    'pengaturan.kelola',
                    SettingsMenuRow(
                      label: 'Outlet dan struk',
                      value: 'Atur',
                      onTap: () => context.push('/lainnya/outlet-struk'),
                    ),
                  ),
                  Consumer(
                    builder: (context, ref, _) {
                      final pengaturanPrinter = ref.watch(
                        pengaturanPrinterProvider,
                      );
                      final namaPrinter = pengaturanPrinter.maybeWhen(
                        data: (p) => p?.namaPrinter,
                        orElse: () => null,
                      );
                      return SettingsMenuRow(
                        label: 'Printer struk',
                        value: namaPrinter ?? 'Belum diatur',
                        onTap: () => context.push('/lainnya/printer'),
                      );
                    },
                  ),
                  bila(
                    'pengaturan.kelola',
                    SettingsMenuRow(
                      label: 'Metode pembayaran',
                      value: 'Atur',
                      onTap: () => context.push('/lainnya/metode-bayar'),
                    ),
                  ),
                  bila(
                    'produk.kelola',
                    SettingsMenuRow(
                      label: 'Kategori produk',
                      value: 'Atur',
                      onTap: () => context.push('/kategori'),
                    ),
                  ),
                  bila(
                    'produk.kelola',
                    SettingsMenuRow(
                      label: 'Varian & tambahan',
                      value: 'Atur',
                      onTap: () => context.push('/grup-tambahan'),
                    ),
                  ),
                  bila(
                    'pengaturan.kelola',
                    SettingsMenuRow(
                      label: 'Tipe pesanan & meja',
                      value: 'Atur',
                      onTap: () => context.push('/tipe-order-meja'),
                    ),
                  ),
                  bila(
                    'pengaturan.kelola',
                    SettingsMenuRow(
                      label: 'Level member & poin',
                      value: 'Atur',
                      onTap: () => context.push('/level-member-poin'),
                    ),
                  ),
                  bila(
                    'promo.kelola',
                    SettingsMenuRow(
                      label: 'Pajak dan service',
                      value: 'Atur',
                      onTap: () => context.push('/pajak'),
                    ),
                  ),
                  bila(
                    'promo.kelola',
                    FiturTerkunci(
                      kode: 'diskon',
                      child: SettingsMenuRow(
                        label: 'Promo',
                        value: 'Atur',
                        onTap: () => context.push('/promo'),
                        showDivider: false,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            const SectionHeader(label: 'Akun'),
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  bila(
                    'pengguna.kelola',
                    SettingsMenuRow(
                      label: 'Karyawan dan hak akses',
                      value: '$jumlahKaryawan orang',
                      onTap: () => context.push('/pengguna'),
                    ),
                  ),
                  bila(
                    'pengaturan.kelola',
                    SettingsMenuRow(
                      label: 'Paket langganan',
                      value: 'Atur',
                      onTap: () => context.push('/lainnya/paket-langganan'),
                      showDivider: true,
                    ),
                  ),
                  SettingsMenuRow(
                    label: 'Keluar / ganti kasir',
                    value: penggunaSaatIni?.nama ?? '',
                    onTap: () {
                      ref.read(currentPenggunaIdProvider.notifier).logout();
                      context.go('/');
                    },
                    showDivider: false,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
