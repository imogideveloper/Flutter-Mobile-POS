import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/core/network/auth_session_store.dart';
import 'package:apps_pos/core/providers/database_provider.dart';
import 'package:apps_pos/core/providers/device_pairing_provider.dart';
import 'package:apps_pos/main.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// devicePairedProvider sengaja di-override ke `true` di semua test file ini
// - flutter_secure_storage tidak punya platform channel di widget test,
// jadi baca aslinya akan hang pumpAndSettle tanpa pernah resolve. Test di
// sini soal alur PIN pilih-pengguna, bukan soal pairing OTP, jadi aman
// dianggap device sudah pernah di-pairing sebelumnya.
void main() {
  testWidgets('login sebagai Owner default dengan PIN -> masuk ke Kasir',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWith((ref) => db),
        devicePairedProvider.overrideWith((ref) async => true),
        // authBootstrapProvider jalan dgn devicePaired=true, lalu baca
        // AuthSessionStore.muat() lewat secureStorageProvider yang TIDAK
        // ada platform channel di widget test (lihat komentar di atas) -
        // di-override no-op di sini supaya tidak ikut hang.
        authBootstrapProvider.overrideWith((ref) async {}),
      ],
      child: const AppsPosApp(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Siapa yang pegang kasir?'), findsOneWidget);
    expect(find.text('Owner (default)'), findsOneWidget);

    await tester.tap(find.text('Owner (default)'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('loginForm.pin')), '000000');
    await tester.tap(find.byKey(const Key('loginForm.masuk')));
    await tester.pumpAndSettle();

    expect(find.text('Buka shift dulu sebelum mulai transaksi'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('PIN salah ditolak, tetap di halaman login', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWith((ref) => db),
        devicePairedProvider.overrideWith((ref) async => true),
        // authBootstrapProvider jalan dgn devicePaired=true, lalu baca
        // AuthSessionStore.muat() lewat secureStorageProvider yang TIDAK
        // ada platform channel di widget test (lihat komentar di atas) -
        // di-override no-op di sini supaya tidak ikut hang.
        authBootstrapProvider.overrideWith((ref) async {}),
      ],
      child: const AppsPosApp(),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Owner (default)'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('loginForm.pin')), '111111');
    await tester.tap(find.byKey(const Key('loginForm.masuk')));
    await tester.pumpAndSettle();

    expect(find.text('PIN salah'), findsOneWidget);
    expect(find.text('Siapa yang pegang kasir?'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
