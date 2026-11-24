import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/features/produk/data/local/tables/produk_table.dart' hide Produk;
import 'package:apps_pos/features/produk/presentation/pages/grup_tambahan_page.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

/// Ditemukan di HP 2026-11-24: tombol "Produk yang memakai grup ini" tidak berbuat apa pun (dialog tidak pernah
/// terbuka), karena `await ref.read(produkSemuaProvider.future)` menunggu tanpa akhir (bug yang sama dengan tombol
/// Tukar poin di keranjang).
void main() {
  testWidgets('"Produk yang memakai grup ini" membuka dialog pilihan produk', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.produkDao.upsertProduk(ProdukCompanion.insert(
      id: 'p1',
      tokoId: 'toko-default',
      nama: 'Kopi Susu',
      tipe: ProdukTipe.barang,
      hargaJual: const Value(18000),
      createdAt: 0,
      updatedAt: 0,
    ));
    await db.produkDao.upsertGrupModifier(GrupModifierCompanion.insert(
      id: 'g1',
      tokoId: 'toko-default',
      nama: 'Ukuran',
      createdAt: 0,
      updatedAt: 0,
    ));

    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: overridesSudahLogin(db),
      child: const MaterialApp(home: GrupTambahanDetailPage(grupId: 'g1')),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('grup_tambahan.produk')));
    // Dialog dibuka setelah membaca daftar produk dari basis data (async nyata): beri waktu nyata sebelum memompa frame.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();

    expect(find.text('Produk untuk Ukuran'), findsOneWidget, reason: 'dialog pilihan produk harus terbuka');
    expect(find.text('Kopi Susu'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
