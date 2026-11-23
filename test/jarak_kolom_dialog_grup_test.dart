import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/core/providers/database_provider.dart';
import 'package:apps_pos/features/produk/presentation/pages/grup_tambahan_page.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

/// Ditemukan di HP 2026-11-24: dialog "Grup baru" (Varian & tambahan) menampilkan kolom Nama, Minimal, dan Maksimal
/// saling menempel sehingga label mengambang bertabrakan.
void main() {
  testWidgets('dialog Grup baru: kolom Nama, Minimal, dan Maksimal berjarak', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: [appDatabaseProvider.overrideWith((ref) => db)],
      child: const MaterialApp(home: GrupTambahanPage()),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('grup_tambahan.tambah')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('grup.nama')), findsOneWidget);
    expect(find.byKey(const Key('grup.min')), findsOneWidget);
    expect(find.byKey(const Key('grup.maks')), findsOneWidget);
    pastikanKolomBerjarak(tester);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
