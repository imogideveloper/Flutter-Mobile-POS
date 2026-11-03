import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/auth_session_store.dart';
import '../../../../core/network/dio_backend_api.dart';
import '../../../../core/providers/seed_provider.dart';
import '../../../../core/providers/session_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/avatar_initial.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../fitur/presentation/providers/feature_gate_provider.dart';
import '../../data/pengguna_repository.dart';
import '../../domain/pengguna.dart';
import '../providers/auth_providers.dart';
import 'otp_login_page.dart';

class LoginPage extends ConsumerWidget {
  const LoginPage({super.key});

  Future<void> _pilihPengguna(BuildContext context, WidgetRef ref, Pengguna pengguna) async {
    final pin = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => _PinLoginSheet(pengguna: pengguna),
    );
    if (pin == null || pin.isEmpty) return;

    final hasil = await ref.read(penggunaRepositoryProvider).verifikasiPin(pengguna.id, pin);
    if (!context.mounted) return;

    final pesan = switch (hasil) {
      HasilVerifikasiPin.berhasil => null,
      HasilVerifikasiPin.pinSalah => 'PIN salah',
      HasilVerifikasiPin.terkunci =>
        'Terlalu banyak PIN salah - akun dikunci sementara, coba lagi beberapa menit lagi',
      HasilVerifikasiPin.nonaktif => 'Akun ini sudah tidak aktif - hubungi owner',
      HasilVerifikasiPin.tidakDitemukan => 'Akun tidak ditemukan',
    };
    if (pesan != null) {
      showAppToast(context, message: pesan, variant: ToastVariant.warning);
      return;
    }

    ref.read(currentPenggunaIdProvider.notifier).login(pengguna.id);
    ref.invalidate(featureGateProvider);

    // Tahap 5b (desain #6) - setelah login OFFLINE berhasil, coba upgrade
    // ke token ONLINE atas nama karyawan ybs (best-effort, bukan blocker -
    // kalau offline/gagal, login lokal di atas sudah cukup utk masuk ke
    // Kasir; panggilan online langsung spt refund/layar kelola baru butuh
    // token ini begitu benar2 dipanggil, bukan di titik ini).
    unawaited(_cobaUpgradeTokenOnline(ref, pengguna, pin));

    if (!context.mounted) return;
    context.go('/kasir');
  }

  Future<void> _cobaUpgradeTokenOnline(WidgetRef ref, Pengguna pengguna, String pin) async {
    try {
      final sesi = await ref.read(authSessionStoreProvider).muat();
      final serverPenggunaId = await ref.read(penggunaRepositoryProvider).serverIdUntuk(pengguna.id);
      if (sesi == null || serverPenggunaId == null) return;

      // PIN sudah benar (sudah lolos verifikasi OFFLINE di atas), dikirim
      // lagi ke server murni utk mendapat token - server tetap
      // memverifikasi ulang sendiri, tidak pernah mempercayai klaim HP
      // (lihat routers/auth.py::pin_login).
      final hasil = await ref.read(backendApiProvider).pinLoginOnline(
            perangkatId: sesi.perangkatId,
            penggunaId: serverPenggunaId,
            pin: pin,
          );
      await ref.read(authSessionStoreProvider).simpan(SesiBackend(
            accessToken: hasil.accessToken,
            refreshToken: hasil.refreshToken,
            tokoId: sesi.tokoId,
            outletId: sesi.outletId,
            penggunaId: hasil.penggunaId,
            perangkatId: sesi.perangkatId,
          ));
    } catch (_) {
      // Diam-diam - lihat docstring di atas pemanggil.
    }
  }

  /// Device SUDAH paired, jadi AuthGatePage tidak pernah lagi menampilkan
  /// OtpLoginPage sendiri (lihat auth_gate_page.dart) - satu-satunya jalan
  /// balik ke sana (khusus utk "lupa PIN kasir?", lihat catatan _lupaPin
  /// di otp_login_page.dart) adalah push manual di sini, bukan lewat
  /// go_router (halaman itu memang tidak dikasih route sendiri). onSelesai
  /// tinggal pop - providers (devicePairedProvider dkk) sudah reaktif,
  /// LoginPage di bawahnya otomatis ter-refresh dgn PIN baru begitu balik.
  void _bukaLupaPin(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => OtpLoginPage(onSelesai: () => Navigator.of(context).pop()),
    ));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seed = ref.watch(seedProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('Siapa yang pegang kasir?')),
      // Tunggu seedProvider dulu - instalasi pertama belum punya baris
      // Pengguna sama sekali sebelum seed role/owner default jalan.
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.lg, AppSpacing.xl, AppSpacing.sm),
            child: Text('Pilih akun untuk mulai bertugas', style: AppTypography.secondary),
          ),
          Expanded(
            child: seed.when(
              data: (_) => _DaftarPengguna(onPilih: (p) => _pilihPengguna(context, ref, p)),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) => Center(child: Text('Gagal menyiapkan data: $error')),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Center(
                child: TextButton.icon(
                  key: const Key('loginPage.lupaPin'),
                  onPressed: () => _bukaLupaPin(context),
                  icon: const Icon(Icons.lock_reset_outlined, size: 18),
                  label: const Text('Lupa PIN kasir?'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DaftarPengguna extends ConsumerWidget {
  const _DaftarPengguna({required this.onPilih});

  final void Function(Pengguna pengguna) onPilih;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokoId = ref.watch(currentTokoIdProvider);
    final penggunaAktif = ref.watch(penggunaAktifProvider(tokoId));

    return penggunaAktif.when(
      data: (items) => items.isEmpty
          ? const EmptyState(
              icon: Icons.people_outline,
              message: 'Belum ada pengguna - hubungi owner',
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.xl),
              itemCount: items.length,
              separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, index) {
                final pengguna = items[index];
                return _PenggunaCard(pengguna: pengguna, onTap: () => onPilih(pengguna));
              },
            ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => Center(child: Text('Gagal memuat pengguna: $error')),
    );
  }
}

class _PenggunaCard extends StatelessWidget {
  const _PenggunaCard({required this.pengguna, required this.onTap});

  final Pengguna pengguna;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          AvatarInitial.fromName(
            pengguna.nama,
            background: AppColors.primaryTint,
            foreground: AppColors.primaryDark,
            size: 44,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(pengguna.nama, style: AppTypography.bodyEmphasis),
                const SizedBox(height: 2),
                Text(pengguna.roleNama, style: AppTypography.secondary),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
        ],
      ),
    );
  }
}

/// Bottom sheet masuk pakai PIN - dibalik dari AlertDialog polos lama (atas
/// permintaan eksplisit "tampilan lebih modern") ke pola modal yang sama
/// dgn modal pembayaran di paket_langganan_page.dart, supaya satu bahasa
/// visual di seluruh app.
class _PinLoginSheet extends StatefulWidget {
  const _PinLoginSheet({required this.pengguna});

  final Pengguna pengguna;

  @override
  State<_PinLoginSheet> createState() => _PinLoginSheetState();
}

class _PinLoginSheetState extends State<_PinLoginSheet> {
  final _formKey = GlobalKey<FormState>();
  final _pinController = TextEditingController();

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(_pinController.text);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.lg,
          AppSpacing.xl,
          AppSpacing.xl + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.borderStrong,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Row(
                children: [
                  AvatarInitial.fromName(
                    widget.pengguna.nama,
                    background: AppColors.primaryTint,
                    foreground: AppColors.primaryDark,
                    size: 48,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Masuk sebagai', style: AppTypography.secondary),
                        Text(widget.pengguna.nama, style: AppTypography.headerTitle),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xxl),
              Text('PIN kasir', style: AppTypography.bodyEmphasis.copyWith(fontSize: 13)),
              const SizedBox(height: AppSpacing.xs),
              TextFormField(
                key: const Key('loginForm.pin'),
                controller: _pinController,
                autofocus: true,
                obscureText: true,
                maxLength: 6,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: AppTypography.headerTitle.copyWith(fontSize: 26, letterSpacing: 10),
                decoration: const InputDecoration(counterText: ''),
                validator: (value) {
                  if (value == null || value.length != 6 || int.tryParse(value) == null) {
                    return 'PIN harus 6 digit angka';
                  }
                  return null;
                },
                onFieldSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: AppSpacing.xl),
              Row(
                children: [
                  Expanded(
                    child: AppSecondaryButton(
                      label: 'Batal',
                      fullWidth: true,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: AppPrimaryButton(
                      key: const Key('loginForm.masuk'),
                      label: 'Masuk',
                      onPressed: _submit,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
