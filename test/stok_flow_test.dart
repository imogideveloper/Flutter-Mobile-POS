import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/features/produk/data/local/tables/produk_table.dart' hide Produk;
import 'package:apps_pos/features/produk/domain/produk.dart';
import 'package:apps_pos/main.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

void main() {
  testWidgets('produk -> stok -> catat mutasi -> muncul di list stok',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await db.produkDao.upsertProduk(ProdukCompanion.insert(
      id: 'p1',
      tokoId: 'toko-default',
      nama: 'Kopi Hitam',
      tipe: ProdukTipe.barang,
      hargaJual: const Value(15000),
      createdAt: 0,
      updatedAt: 0,
    ));

    await tester.pumpWidget(ProviderScope(
      overrides: overridesSudahLogin(db),
      child: const AppsPosApp(),
    ));
    await tester.pumpAndSettle();

    // App mendarat di tab Kasir (default) - pindah ke tab Produk dulu,
    // tombol "Kelola stok" ada di AppBar halaman itu.
    await tester.tap(find.text('Produk'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Kelola stok'));
    await tester.pumpAndSettle();

    expect(find.text('Stok'), findsOneWidget);
    expect(find.text('Belum ada saldo stok di outlet ini'), findsOneWidget);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(find.text('Catat Mutasi Stok'), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<Produk>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kopi Hitam').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Qty'), '5');

    await tester.tap(find.widgetWithText(FilledButton, 'Simpan'));
    await tester.pumpAndSettle();

    expect(find.text('Catat Mutasi Stok'), findsNothing);
    expect(find.text('Stok'), findsOneWidget);
    // Muncul 2x: baris "Semua stok" dan baris "Mutasi terakhir".
    expect(find.text('Kopi Hitam'), findsWidgets);
    expect(find.text('5'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
