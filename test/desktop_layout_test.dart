import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/core/utils/platform_perangkat.dart';
import 'package:apps_pos/core/widgets/app_bottom_nav_bar.dart';
import 'package:apps_pos/core/widgets/barcode_scan_page.dart';
import 'package:apps_pos/main.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

Future<void> _bukaAplikasi(WidgetTester tester, double lebar, double tinggi) async {
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  await seedMetodeBayarUjiCoba(db);
  tester.view.physicalSize = Size(lebar, tinggi);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(overrides: overridesSudahLogin(db), child: const AppsPosApp()));
  await tester.pumpAndSettle();
}

Future<void> _tutup(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 1));
}

void main() {
  test('kamera pemindai hanya di Android/iOS', () {
    for (final p in TargetPlatform.values) {
      debugDefaultTargetPlatformOverride = p;
      final seharusnya = p == TargetPlatform.android || p == TargetPlatform.iOS;
      expect(adaKameraPemindai, seharusnya, reason: '$p');
    }
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('layar lebar (desktop): navigasi samping, tanpa navigasi bawah, dan bisa pindah tab', (tester) async {
    await _bukaAplikasi(tester, 1400, 900);

    expect(find.byKey(const Key('appNavRail')), findsOneWidget);
    expect(find.byType(AppBottomNavBar), findsNothing);

    await tester.tap(find.descendant(of: find.byKey(const Key('appNavRail')), matching: find.text('Riwayat')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('appNavRail')), findsOneWidget, reason: 'rail tetap ada setelah pindah tab');

    await _tutup(tester);
  });

  testWidgets('layar ponsel: tetap navigasi bawah, tanpa rail', (tester) async {
    await _bukaAplikasi(tester, 420, 900);

    expect(find.byType(AppBottomNavBar), findsOneWidget);
    expect(find.byKey(const Key('appNavRail')), findsNothing);

    await _tutup(tester);
  });

  testWidgets('desktop: pindai barcode memakai dialog ketik/scan, bukan kamera', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;

    String? hasil = 'belum';
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            key: const Key('uji.pindai'),
            onPressed: () async => hasil = await pindaiBarcode(context),
            child: const Text('Pindai'),
          ),
        ),
      ),
    ));

    await tester.tap(find.byKey(const Key('uji.pindai')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('barcodeManual.dialog')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('barcodeManual.input')), '8991234567890');
    await tester.tap(find.byKey(const Key('barcodeManual.ok')));
    await tester.pumpAndSettle();
    expect(hasil, '8991234567890');

    // Dibatalkan -> null
    await tester.tap(find.byKey(const Key('uji.pindai')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Batal'));
    await tester.pumpAndSettle();
    expect(hasil, isNull);

    // Override platform WAJIB dikembalikan sebelum tes berakhir.
    debugDefaultTargetPlatformOverride = null;
  });
}
