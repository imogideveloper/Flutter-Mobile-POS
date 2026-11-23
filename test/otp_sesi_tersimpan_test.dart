import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/core/network/backend_api.dart';
import 'package:apps_pos/core/network/dio_backend_api.dart';
import 'package:apps_pos/core/providers/database_provider.dart';
import 'package:apps_pos/core/providers/device_pairing_provider.dart';
import 'package:apps_pos/main.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// Penyimpanan aman sungguhan di HP memakai panggilan platform yang butuh waktu, sehingga layar sempat
/// berpindah di antara dua penulisan. Versi palsu yang selesai seketika menyembunyikan masalahnya.
class _PenyimpananLambat extends FlutterSecureStorage {
  const _PenyimpananLambat();

  @override
  Future<void> write({required String key, required String? value, AppleOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, WebOptions? webOptions, AppleOptions? mOptions, WindowsOptions? wOptions}) async {
    await Future<void>.delayed(const Duration(milliseconds: 30));
    return super.write(key: key, value: value, iOptions: iOptions, aOptions: aOptions, lOptions: lOptions, webOptions: webOptions, mOptions: mOptions, wOptions: wOptions);
  }
}

class _ApiOtpBerhasil implements BackendApi {
  @override
  Future<OtpRequestResult> otpRequest({required String noHp}) async => const OtpRequestResult(expiresIn: 300);

  @override
  Future<AuthResult> otpVerify({
    required String noHp,
    required String kode,
    required String deviceUid,
    required String namaPerangkat,
    String? platform,
    String? namaToko,
    String? jenisUsaha,
    String? namaPemilik,
    String? pin,
  }) async =>
      const AuthResult(
        accessToken: 'akses',
        refreshToken: 'segar',
        tokoId: 'toko-server',
        tokoNama: 'Toko Uji',
        outletId: 'outlet-server',
        outletNama: 'Outlet Uji',
        outletKode: 'OUT1',
        penggunaId: 'pengguna-server',
        penggunaNama: 'Pemilik Uji',
        perangkatId: 'perangkat-server',
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// Ditemukan di HP 2026-11-23: setelah masuk dengan OTP, aplikasi memang terbuka sampai kasir, tetapi setiap
/// dimulai ulang kembali ke layar OTP. Penyebab: tanda "paired" ditulis di langkah terakhir, sesudah login
/// memindahkan layar ke kasir dan melepas halaman OTP, sehingga penulisannya gagal diam-diam.
void main() {
  testWidgets('selesai masuk dengan OTP menyimpan tanda paired, supaya restart tidak kembali ke layar OTP',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWith((ref) => db),
        backendApiProvider.overrideWithValue(_ApiOtpBerhasil()),
        secureStorageProvider.overrideWithValue(const _PenyimpananLambat()),
      ],
      child: const AppsPosApp(),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('otpLogin.nomorHp')), findsOneWidget, reason: 'belum paired: layar OTP');
    await tester.enterText(find.byKey(const Key('otpLogin.nomorHp')), '081234567890');
    await tester.tap(find.byKey(const Key('otpLogin.kirim')));
    await tester.pumpAndSettle();

    for (var i = 0; i < 6; i++) {
      await tester.enterText(find.byKey(Key('otpLogin.kode$i')), '${i + 1}');
    }
    await tester.tap(find.byKey(const Key('otpLogin.kirim')));
    // Di HP layar terus digambar selagi alur login berjalan, jadi perpindahan ke kasir bisa terjadi di tengah
    // langkah-langkahnya. Tes meniru itu dengan memproses frame bergantian dengan penantian nyata.
    for (var i = 0; i < 120; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pumpAndSettle();

    const penyimpanan = FlutterSecureStorage();
    expect(await penyimpanan.read(key: 'backend_access_token'), 'akses', reason: 'sesi tersimpan');
    expect(await penyimpanan.read(key: 'device_paired'), 'true',
        reason: 'tanpa tanda ini, restart aplikasi kembali ke layar OTP');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
