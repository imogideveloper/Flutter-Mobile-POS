import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/main.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

void main() {
  testWidgets('buka shift -> catat kas -> tutup shift', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(ProviderScope(
      overrides: overridesSudahLogin(db),
      child: const AppsPosApp(),
    ));
    await tester.pumpAndSettle();

    // App mendarat di tab Kasir (default) - pindah ke tab Produk dulu,
    // PopupMenuButton menu lainnya ada di AppBar halaman itu.
    await tester.tap(find.text('Produk'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shift'));
    await tester.pumpAndSettle();

    expect(find.text('Tidak ada shift terbuka di outlet ini'), findsOneWidget);

    await tester.tap(find.text('Buka Shift'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('bukaShiftForm.modalAwal')), '100000');
    await tester.tap(find.text('Mulai shift'));
    await tester.pumpAndSettle();

    expect(find.text('Shift sedang berjalan'), findsOneWidget);
    expect(find.text('Rp100.000'), findsOneWidget);

    await tester.tap(find.text('Catat Kas Masuk/Keluar'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Jumlah (Rp)'), '20000');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Keterangan'), 'Beli plastik');
    await tester.tap(find.widgetWithText(FilledButton, 'Simpan'));
    await tester.pumpAndSettle();

    expect(find.text('Shift sedang berjalan'), findsOneWidget);

    await tester.tap(find.text('Tutup Shift'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Kas seharusnya (Rp)'), '80000');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Kas aktual di laci (Rp)'), '80000');
    await tester.tap(find.byKey(const Key('tutupShiftForm.submit')));
    await tester.pumpAndSettle();

    expect(find.text('Tidak ada shift terbuka di outlet ini'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
