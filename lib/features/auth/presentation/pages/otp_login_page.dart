import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/network/auth_session_store.dart';
import '../../../../core/network/backend_exception.dart';
import '../../../../core/network/dio_backend_api.dart';
import '../../../../core/providers/device_pairing_provider.dart';
import '../../../../core/providers/session_provider.dart';
import '../../../../core/providers/toko_profile_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_toast.dart';
import '../providers/auth_providers.dart';

const _panjangOtp = 6;
const _detikKirimUlang = 60;

enum _Mode { masuk, daftar }

/// Pairing device satu kali lewat OTP WhatsApp (mode Masuk) atau
/// pendaftaran toko baru (mode Daftar) - BUKAN login harian. Setelah
/// berhasil (atau lewat "Masuk dengan PIN karyawan"), ganti kasir
/// sehari-hari tetap lewat pilih-pengguna+PIN (LoginPage) seperti biasa -
/// lihat devicePairedProvider.
///
/// `/auth/otp/request` & `/auth/otp/verify` dipanggil SUNGGUHAN ke backend
/// (lihat backendApiProvider) - provider OTP server masih mock (log ke
/// stdout server, belum WhatsApp sungguhan, lihat backend/app/services/
/// otp_service.py), jadi utk testing manual kode OTP harus dibaca dari log
/// server, TIDAK ditampilkan di app ini (beda dgn versi stub sebelumnya).
class OtpLoginPage extends ConsumerStatefulWidget {
  const OtpLoginPage({super.key, required this.onSelesai, this.onMasukDenganPin});

  /// Dipanggil setelah OTP berhasil ATAU user pilih "Masuk dengan PIN
  /// karyawan" - AuthGatePage lanjut menampilkan LoginPage (pilih
  /// pengguna+PIN) sesudah ini.
  final VoidCallback onSelesai;

  /// Tombol "Masuk dengan PIN karyawan" hanya bermakna bila ada layar PIN untuk dituju, yaitu saat
  /// halaman ini dibuka dari LoginPage di perangkat yang SUDAH dipasangkan. Di perangkat baru
  /// (belum ada data karyawan, belum terhubung ke toko) diisi null dan tombolnya disembunyikan
  /// (BUG-009: dulu tombolnya ada tetapi tidak melakukan apa pun).
  final VoidCallback? onMasukDenganPin;

  @override
  ConsumerState<OtpLoginPage> createState() => _OtpLoginPageState();
}

class _OtpLoginPageState extends ConsumerState<OtpLoginPage> {
  _Mode _mode = _Mode.masuk;
  final _formKey = GlobalKey<FormState>();

  // Mode daftar saja.
  final _namaTokoController = TextEditingController();
  final _namaPemilikController = TextEditingController();
  final _pinController = TextEditingController();
  final _konfirmasiPinController = TextEditingController();
  JenisUsaha _jenisUsaha = JenisUsaha.kafe;

  /// Mode masuk saja - "lupa PIN kasir?". OTP WhatsApp yang diverifikasi
  /// sendiri sudah membuktikan kepemilikan nomor HP terdaftar, jadi aman
  /// dipakai sbg jalur reset PIN device TANPA perlu tahu PIN lama (lihat
  /// backend/app/routers/auth.py::verifikasi_otp) - beda dari "Reset PIN"
  /// di menu Karyawan (itu Owner mereset PIN KARYAWAN LAIN, butuh sudah
  /// login duluan, tidak bisa dipakai kalau Owner sendiri yang lupa PIN).
  bool _lupaPin = false;

  // Dipakai kedua mode.
  final _nomorController = TextEditingController();
  final _otpControllers = List.generate(_panjangOtp, (_) => TextEditingController());
  final _otpFocusNodes = List.generate(_panjangOtp, (_) => FocusNode());
  String? _kodeTerkirimKe;
  Timer? _timer;
  int _detikSisa = 0;
  bool _memproses = false;

  @override
  void dispose() {
    _namaTokoController.dispose();
    _namaPemilikController.dispose();
    _pinController.dispose();
    _konfirmasiPinController.dispose();
    _nomorController.dispose();
    for (final c in _otpControllers) {
      c.dispose();
    }
    for (final f in _otpFocusNodes) {
      f.dispose();
    }
    _timer?.cancel();
    super.dispose();
  }

  void _gantiMode(_Mode mode) {
    setState(() {
      _mode = mode;
      _lupaPin = false;
      _kodeTerkirimKe = null;
      _timer?.cancel();
      _detikSisa = 0;
      for (final c in _otpControllers) {
        c.clear();
      }
    });
  }

  Future<void> _kirimKode() async {
    if ((_mode == _Mode.daftar || _lupaPin) && !(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final nomor = _nomorController.text.trim();
    if (_mode == _Mode.masuk && nomor.length < 8) {
      showAppToast(context, message: 'Masukkan nomor HP yang valid', variant: ToastVariant.warning);
      return;
    }

    setState(() => _memproses = true);
    try {
      await ref.read(backendApiProvider).otpRequest(noHp: nomor);
      if (!mounted) return;
      setState(() {
        _kodeTerkirimKe = nomor;
        _detikSisa = _detikKirimUlang;
      });
      showAppToast(context, message: 'Kode OTP dikirim lewat WhatsApp', variant: ToastVariant.success);

      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (_detikSisa <= 1) {
          timer.cancel();
          setState(() => _detikSisa = 0);
          return;
        }
        setState(() => _detikSisa -= 1);
      });

      FocusScope.of(context).requestFocus(_otpFocusNodes.first);
    } on BackendException catch (e) {
      if (mounted) showAppToast(context, message: e.message, variant: ToastVariant.danger);
    } finally {
      if (mounted) setState(() => _memproses = false);
    }
  }

  Future<void> _verifikasiOtp() async {
    final kode = _otpControllers.map((c) => c.text).join();
    if (kode.length != _panjangOtp) {
      showAppToast(context, message: 'Kode OTP belum lengkap', variant: ToastVariant.warning);
      return;
    }

    setState(() => _memproses = true);
    try {
      final deviceUid = await ambilDeviceUid(ref);
      // Dikirim di dua kasus: mode daftar (PIN awal akun baru) ATAU mode
      // masuk dgn "lupa PIN" dicentang (reset PIN device - lihat catatan
      // _lupaPin di atas).
      final pinUntukDikirim = (_mode == _Mode.daftar || _lupaPin) ? _pinController.text : null;
      final hasil = await ref.read(backendApiProvider).otpVerify(
            noHp: _kodeTerkirimKe!,
            kode: kode,
            deviceUid: deviceUid,
            namaPerangkat: 'Perangkat ${defaultTargetPlatform.name}',
            platform: defaultTargetPlatform.name,
            namaToko: _mode == _Mode.daftar ? _namaTokoController.text.trim() : null,
            jenisUsaha: _mode == _Mode.daftar ? _jenisUsaha.kode : null,
            namaPemilik: _mode == _Mode.daftar ? _namaPemilikController.text.trim() : null,
            pin: pinUntukDikirim,
          );

      final tokoIdLama = ref.read(currentTokoIdProvider);
      await ref.read(penggunaRepositoryProvider).terapkanIdentitasBackend(
            tokoIdLama: tokoIdLama,
            tokoIdBaru: hasil.tokoId,
            penggunaIdBaru: hasil.penggunaId,
            namaDariBackend: hasil.penggunaNama,
            pin: pinUntukDikirim,
          );
      final pairingDao = ref.read(pairingDaoProvider);
      await pairingDao.migrasikanTokoId(dari: tokoIdLama, ke: hasil.tokoId);

      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      await pairingDao.upsertOutlet(OutletsCompanion.insert(
        id: hasil.outletId,
        tokoId: hasil.tokoId,
        kode: hasil.outletKode,
        nama: hasil.outletNama,
        createdAt: now,
        updatedAt: now,
      ));
      await pairingDao.upsertPerangkat(PerangkatCompanion.insert(
        id: hasil.perangkatId,
        tokoId: hasil.tokoId,
        outletId: Value(hasil.outletId),
        nama: 'Perangkat ${defaultTargetPlatform.name}',
        deviceUid: deviceUid,
        platform: Value(defaultTargetPlatform.name),
        createdAt: now,
        updatedAt: now,
      ));

      await ref.read(authSessionStoreProvider).simpan(SesiBackend(
            accessToken: hasil.accessToken,
            refreshToken: hasil.refreshToken,
            tokoId: hasil.tokoId,
            outletId: hasil.outletId,
            penggunaId: hasil.penggunaId,
            perangkatId: hasil.perangkatId,
          ));

      ref.read(currentTokoIdProvider.notifier).set(hasil.tokoId);
      ref.read(currentOutletIdProvider.notifier).set(hasil.outletId);
      ref.read(currentPerangkatIdProvider.notifier).set(hasil.perangkatId);
      ref.read(currentPenggunaIdProvider.notifier).login(hasil.penggunaId);

      if (_mode == _Mode.daftar) {
        await simpanTokoProfile(
          ref,
          namaToko: _namaTokoController.text.trim(),
          jenisUsaha: _jenisUsaha,
          namaPemilik: _namaPemilikController.text.trim(),
        );
      }
      await tandaiDeviceSudahPaired(ref);
      if (mounted) widget.onSelesai();
    } on BackendException catch (e) {
      if (mounted) showAppToast(context, message: e.message, variant: ToastVariant.danger);
    } catch (e) {
      // Backend sudah terlanjur sukses sebelum langkah lokal ini (toko
      // sudah kebuat di server) - kalau step lokal (DB/secure storage)
      // gagal, jangan biarkan user "stuck" tanpa pesan sama sekali kayak
      // sebelumnya (BackendException doang yang ketangkep di atas).
      if (mounted) {
        showAppToast(context, message: 'Gagal menyimpan sesi lokal: $e', variant: ToastVariant.danger);
      }
    } finally {
      if (mounted) setState(() => _memproses = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tahapOtp = _kodeTerkirimKe != null;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: AppSpacing.xl),
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.point_of_sale_outlined, color: Colors.white, size: 22),
                ),
                const SizedBox(height: AppSpacing.xxl),
                Text(
                  _mode == _Mode.masuk ? 'Masuk ke kasir' : 'Daftar toko baru',
                  style: AppTypography.headerTitle.copyWith(fontSize: 26),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _mode == _Mode.masuk
                      ? 'Pakai nomor HP yang terdaftar di toko kamu. Kode masuk dikirim lewat WhatsApp.'
                      : 'Gratis untuk mulai. Isi data toko kamu, lalu verifikasi nomor HP.',
                  style: AppTypography.secondary.copyWith(fontSize: 14),
                ),
                const SizedBox(height: AppSpacing.xxl),
                if (!tahapOtp && _mode == _Mode.daftar) ..._formDaftar(),
                if (!tahapOtp) ...[
                  Text('Nomor HP', style: AppTypography.bodyEmphasis.copyWith(fontSize: 13)),
                  const SizedBox(height: AppSpacing.xs),
                  TextFormField(
                    key: const Key('otpLogin.nomorHp'),
                    controller: _nomorController,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(prefixText: '+62 '),
                    validator: _mode == _Mode.daftar
                        ? (value) => (value == null || value.trim().length < 8)
                            ? 'Nomor HP wajib diisi'
                            : null
                        : null,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                ],
                if (!tahapOtp && _mode == _Mode.masuk) ...[
                  Center(
                    child: TextButton(
                      key: const Key('otpLogin.lupaPin'),
                      onPressed: () => setState(() => _lupaPin = !_lupaPin),
                      child: Text(_lupaPin ? 'Batal atur PIN baru' : 'Lupa PIN kasir? Atur PIN baru'),
                    ),
                  ),
                  if (_lupaPin) ..._formPin(),
                  const SizedBox(height: AppSpacing.sm),
                ],
                if (tahapOtp) ..._tahapOtpWidgets(),
                AppPrimaryButton(
                  label: _memproses
                      ? 'Memeriksa...'
                      : (tahapOtp
                          ? (_mode == _Mode.daftar ? 'Daftar' : 'Masuk')
                          : 'Kirim kode'),
                  onPressed: _memproses ? null : (tahapOtp ? _verifikasiOtp : _kirimKode),
                ),
                const SizedBox(height: AppSpacing.sm),
                if (_mode == _Mode.masuk && widget.onMasukDenganPin != null)
                  AppSecondaryButton(
                    key: const Key('otpLogin.masukDenganPin'),
                    label: 'Masuk dengan PIN karyawan',
                    fullWidth: true,
                    onPressed: widget.onMasukDenganPin,
                  ),
                if (_mode == _Mode.masuk && widget.onMasukDenganPin == null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Text(
                      'Perangkat baru dipasangkan oleh pemilik lewat kode OTP. '
                      'Karyawan masuk dengan PIN setelah perangkat dipasangkan.',
                      key: const Key('otpLogin.petunjukKaryawan'),
                      textAlign: TextAlign.center,
                      style: AppTypography.secondary,
                    ),
                  ),
                const SizedBox(height: AppSpacing.lg),
                Center(
                  child: TextButton(
                    onPressed: () =>
                        _gantiMode(_mode == _Mode.masuk ? _Mode.daftar : _Mode.masuk),
                    child: Text(
                      _mode == _Mode.masuk
                          ? 'Belum punya toko? Daftar gratis'
                          : 'Sudah punya toko? Masuk',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _formDaftar() {
    return [
      Text('Nama toko', style: AppTypography.bodyEmphasis.copyWith(fontSize: 13)),
      const SizedBox(height: AppSpacing.xs),
      TextFormField(
        key: const Key('otpLogin.namaToko'),
        controller: _namaTokoController,
        decoration: const InputDecoration(hintText: 'Contoh: Kopi Senja'),
        validator: (value) =>
            (value == null || value.trim().isEmpty) ? 'Nama toko wajib diisi' : null,
      ),
      const SizedBox(height: AppSpacing.lg),
      Text('Jenis usaha', style: AppTypography.bodyEmphasis.copyWith(fontSize: 13)),
      const SizedBox(height: AppSpacing.xs),
      DropdownButtonFormField<JenisUsaha>(
        key: const Key('otpLogin.jenisUsaha'),
        initialValue: _jenisUsaha,
        items: JenisUsaha.values
            .map((j) => DropdownMenuItem(value: j, child: Text(labelJenisUsaha[j]!)))
            .toList(),
        onChanged: (value) => setState(() => _jenisUsaha = value ?? _jenisUsaha),
      ),
      const SizedBox(height: AppSpacing.lg),
      Text('Nama pemilik', style: AppTypography.bodyEmphasis.copyWith(fontSize: 13)),
      const SizedBox(height: AppSpacing.xs),
      TextFormField(
        key: const Key('otpLogin.namaPemilik'),
        controller: _namaPemilikController,
        validator: (value) =>
            (value == null || value.trim().isEmpty) ? 'Nama pemilik wajib diisi' : null,
      ),
      const SizedBox(height: AppSpacing.lg),
      ..._formPin(),
    ];
  }

  /// Dua PIN field (isi + ulangi) - dipakai mode daftar (PIN awal) DAN
  /// mode masuk begitu "Lupa PIN kasir?" dicentang (reset PIN, lihat
  /// catatan _lupaPin di atas).
  List<Widget> _formPin() {
    return [
      Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('PIN kasir', style: AppTypography.bodyEmphasis.copyWith(fontSize: 13)),
                const SizedBox(height: AppSpacing.xs),
                TextFormField(
                  key: const Key('otpLogin.pin'),
                  controller: _pinController,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  maxLength: 6,
                  decoration: const InputDecoration(counterText: ''),
                  validator: (value) {
                    if (value == null || value.length < 4 || value.length > 6) {
                      return '4-6 digit';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Ulangi PIN', style: AppTypography.bodyEmphasis.copyWith(fontSize: 13)),
                const SizedBox(height: AppSpacing.xs),
                TextFormField(
                  key: const Key('otpLogin.konfirmasiPin'),
                  controller: _konfirmasiPinController,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  maxLength: 6,
                  decoration: const InputDecoration(counterText: ''),
                  validator: (value) {
                    if (value != _pinController.text) return 'PIN tidak sama';
                    return null;
                  },
                ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: AppSpacing.xl),
    ];
  }

  List<Widget> _tahapOtpWidgets() {
    return [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Kode OTP', style: AppTypography.bodyEmphasis.copyWith(fontSize: 13)),
          Text('Dikirim ke +62$_kodeTerkirimKe', style: AppTypography.secondary),
        ],
      ),
      const SizedBox(height: AppSpacing.sm),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (var i = 0; i < _panjangOtp; i++)
            SizedBox(
              width: 48,
              child: TextField(
                key: Key('otpLogin.kode$i'),
                controller: _otpControllers[i],
                focusNode: _otpFocusNodes[i],
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                maxLength: 1,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                // contentPadding horizontal GLOBAL (InputDecorationTheme,
                // dirancang utk field lebar normal) kalau dipakai apa
                // adanya di kotak sekecil ini (lebar cuma 48) menyisakan
                // ruang sangat sempit utk 1 digit - glyph-nya kepencet/
                // kepotong di sisi kiri-kanan sampai gak kebaca jelas
                // (padahal controller-nya tetap berisi digit yang benar).
                // Override jadi minimal horizontal di sini saja.
                decoration: const InputDecoration(
                  counterText: '',
                  contentPadding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                ),
                onChanged: (value) {
                  if (value.isNotEmpty && i < _panjangOtp - 1) {
                    FocusScope.of(context).requestFocus(_otpFocusNodes[i + 1]);
                  } else if (value.isEmpty && i > 0) {
                    FocusScope.of(context).requestFocus(_otpFocusNodes[i - 1]);
                  }
                },
              ),
            ),
        ],
      ),
      const SizedBox(height: AppSpacing.sm),
      Text(
        _detikSisa > 0 ? 'Kirim ulang kode dalam 0:${_detikSisa.toString().padLeft(2, '0')}' : '',
        style: AppTypography.secondary,
      ),
      if (_detikSisa == 0)
        TextButton(onPressed: _kirimKode, child: const Text('Kirim ulang kode')),
      const SizedBox(height: AppSpacing.xl),
    ];
  }
}
