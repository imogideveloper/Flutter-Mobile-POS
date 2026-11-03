import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/main.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

/// Smoke test: pastikan kelima tab bottom-nav bisa dibuka tanpa error -
/// terutama Laporan & Lainnya yang banyak gabungan provider (kalau ada yang
/// salah override/wiring, biasanya langsung kelihatan sebagai widget error
/// merah di sini, bukan baru ketahuan manual testing di HP.
void main() {
  testWidgets('kelima tab bottom-nav terbuka tanpa error', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(ProviderScope(
      overrides: overridesSudahLogin(db),
      child: const AppsPosApp(),
    ));
    await tester.pumpAndSettle();

    for (final tab in ['Riwayat', 'Produk', 'Laporan', 'Lainnya', 'Kasir']) {
      await tester.tap(find.text(tab).first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'tab $tab menampilkan error');
    }

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
