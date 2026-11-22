import 'package:apps_pos/core/network/backend_api.dart';
import 'package:apps_pos/core/network/dio_backend_api.dart';
import 'package:apps_pos/features/admin/presentation/providers/admin_providers.dart';
import 'package:apps_pos/features/auth/presentation/pages/otp_login_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _AdminUji extends AdminSesiNotifier {
  String? emailTerakhir;
  String? sandiTerakhir;

  @override
  AdminSesi? build() => null;

  @override
  Future<void> masuk({required String email, required String password}) async {
    emailTerakhir = email;
    sandiTerakhir = password;
    state = AdminSesi(token: 't', nama: 'Admin Uji', email: email);
  }
}

class _ApiOtpUji implements BackendApi {
  @override
  Future<OtpRequestResult> otpRequest({required String noHp}) async => const OtpRequestResult(expiresIn: 300);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Satu pintu masuk: nomor HP -> OTP (pemilik usaha), email atau nama pengguna -> kata sandi (Administrator).
/// Tidak ada tombol "Masuk sebagai Administrator" yang terlihat pengguna usaha.
void main() {
  Future<_AdminUji> buka(WidgetTester tester) async {
    tester.view.physicalSize = const Size(600, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final admin = _AdminUji();
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, _) => OtpLoginPage(onSelesai: () {})),
      GoRoute(path: '/admin', builder: (_, _) => const Text('halaman-dashboard')),
    ]);
    await tester.pumpWidget(ProviderScope(
      overrides: [adminSesiProvider.overrideWith(() => admin)],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();
    return admin;
  }

  Future<void> tutup(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('layar masuk tidak menampilkan tombol Administrator dan memakai satu kolom', (tester) async {
    await buka(tester);
    expect(find.text('Masuk sebagai Administrator'), findsNothing);
    expect(find.byKey(const Key('otpLogin.masukAdmin')), findsNothing);
    expect(find.text('Nomor HP atau email'), findsOneWidget);
    expect(find.byKey(const Key('otpLogin.passwordAdmin')), findsNothing, reason: 'kolom sandi baru muncul untuk email');
    expect(find.text('Kirim kode'), findsOneWidget);
    await tutup(tester);
  });

  testWidgets('tahap OTP: judul "Kode OTP", tanpa keterangan, dan tombol kembali ke isian nomor', (tester) async {
    tester.view.physicalSize = const Size(600, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [backendApiProvider.overrideWithValue(_ApiOtpUji())],
      child: MaterialApp(home: OtpLoginPage(onSelesai: () {})),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Masuk'), findsOneWidget, reason: 'judul bukan "Masuk ke kasir"');
    expect(find.text('Masuk ke kasir'), findsNothing);
    expect(find.textContaining('Pakai nomor HP'), findsNothing);

    await tester.enterText(find.byKey(const Key('otpLogin.nomorHp')), '81234567890');
    await tester.tap(find.byKey(const Key('otpLogin.kirim')));
    await tester.pumpAndSettle();

    expect(find.text('Kode OTP'), findsOneWidget, reason: 'judul saja, tidak ada label lagi di atas kotak');
    expect(find.textContaining('Dikirim ke'), findsNothing);
    expect(find.byKey(const Key('otpLogin.kode0')), findsOneWidget);

    await tester.pump(const Duration(seconds: 10)); // toast "kode terkirim" hilang
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('otpLogin.kembali')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('otpLogin.kode0')), findsNothing);
    expect(find.byKey(const Key('otpLogin.nomorHp')), findsOneWidget);
    await tutup(tester);
  });

  testWidgets('mengetik angka tetap jalur OTP pemilik usaha', (tester) async {
    await buka(tester);
    await tester.enterText(find.byKey(const Key('otpLogin.nomorHp')), '81234567890');
    await tester.pump();
    expect(find.byKey(const Key('otpLogin.passwordAdmin')), findsNothing);
    expect(find.text('Kirim kode'), findsOneWidget);
    expect(find.textContaining('Lupa PIN'), findsNothing, reason: 'reset PIN bukan bagian layar masuk');
    await tutup(tester);
  });

  testWidgets('mengetik email atau nama pengguna menampilkan kata sandi dan masuk ke dashboard admin', (tester) async {
    final admin = await buka(tester);
    await tester.enterText(find.byKey(const Key('otpLogin.nomorHp')), 'Administrator');
    await tester.pump();

    expect(find.byKey(const Key('otpLogin.passwordAdmin')), findsOneWidget);
    expect(find.text('Kirim kode'), findsNothing, reason: 'admin tidak memakai OTP');
    expect(find.textContaining('Lupa PIN'), findsNothing);

    await tester.enterText(find.byKey(const Key('otpLogin.passwordAdmin')), 'sandi-uji-panjang');
    await tester.ensureVisible(find.byKey(const Key('otpLogin.kirim')));
    await tester.tap(find.byKey(const Key('otpLogin.kirim')));
    await tester.pumpAndSettle();

    expect(admin.emailTerakhir, 'Administrator');
    expect(admin.sandiTerakhir, 'sandi-uji-panjang');
    expect(find.text('halaman-dashboard'), findsOneWidget);
    await tutup(tester);
  });

  testWidgets('menghapus huruf mengembalikan ke jalur OTP', (tester) async {
    await buka(tester);
    await tester.enterText(find.byKey(const Key('otpLogin.nomorHp')), 'abc@x.id');
    await tester.pump();
    expect(find.byKey(const Key('otpLogin.passwordAdmin')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('otpLogin.nomorHp')), '8123');
    await tester.pump();
    expect(find.byKey(const Key('otpLogin.passwordAdmin')), findsNothing);
    expect(find.text('Kirim kode'), findsOneWidget);
    await tutup(tester);
  });
}
