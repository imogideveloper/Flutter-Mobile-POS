import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/core/network/auth_session_store.dart';
import 'package:apps_pos/core/providers/database_provider.dart';
import 'package:apps_pos/core/providers/device_pairing_provider.dart';
import 'package:apps_pos/core/providers/toko_profile_provider.dart';
import 'package:apps_pos/main.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// BUG-009: tombol "Masuk dengan PIN karyawan" di perangkat baru tidak melakukan apa pun
/// (AuthGatePage memberi callback kosong). Perangkat yang belum dipasangkan tidak punya data
/// karyawan, jadi tombolnya disembunyikan dan diganti petunjuk. Pada perangkat yang sudah
/// dipasangkan, tombol itu kembali ke layar pilih pengguna + PIN.
void main() {
  Future<void> bukaApp(WidgetTester tester, {required bool dipasangkan}) async {
    tester.view.physicalSize = const Size(600, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWith((ref) => db),
        devicePairedProvider.overrideWith((ref) async => dipasangkan),
        authBootstrapProvider.overrideWith((ref) async {}),
        tokoProfileProvider.overrideWith((ref) async => null),
      ],
      child: const AppsPosApp(),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('perangkat baru (belum dipasangkan): tidak ada tombol PIN mati, ada petunjuk untuk karyawan',
      (tester) async {
    await bukaApp(tester, dipasangkan: false);

    expect(find.text('Siapa yang pegang kasir?'), findsNothing, reason: 'masih di layar OTP');
    expect(find.byKey(const Key('otpLogin.masukDenganPin')), findsNothing);
    expect(find.text('Masuk dengan PIN karyawan'), findsNothing);
    expect(find.byKey(const Key('otpLogin.petunjukKaryawan')), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('perangkat yang sudah dipasangkan: lupa PIN membuka layar OTP dengan tombol PIN yang kembali ke pilih pengguna',
      (tester) async {
    await bukaApp(tester, dipasangkan: true);
    expect(find.text('Siapa yang pegang kasir?'), findsOneWidget);
    expect(find.text('Masuk sebagai Administrator'), findsNothing, reason: 'pengguna usaha tidak melihat jalur admin');

    await tester.tap(find.byKey(const Key('loginPage.lupaPin')));
    await tester.pumpAndSettle();
    expect(find.text('Atur PIN baru'), findsOneWidget);
    expect(find.byKey(const Key('otpLogin.pin')), findsOneWidget, reason: 'kolom PIN baru langsung tampil');
    expect(find.byKey(const Key('otpLogin.masukDenganPin')), findsNothing);
    expect(find.byKey(const Key('otpLogin.petunjukKaryawan')), findsNothing);
    expect(find.text('Belum punya toko? Daftar gratis'), findsNothing);
    expect(find.textContaining('atau email'), findsNothing);

    await tester.tap(find.byKey(const Key('otpLogin.kembali')));
    await tester.pumpAndSettle();
    expect(find.text('Siapa yang pegang kasir?'), findsOneWidget, reason: 'panah kembali ke pilih pengguna');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
