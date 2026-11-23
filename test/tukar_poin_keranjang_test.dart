import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/features/produk/data/local/tables/produk_table.dart' hide Produk;
import 'package:apps_pos/features/stok/data/local/tables/mutasi_stok_table.dart' show MutasiJenis;
import 'package:apps_pos/main.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

/// Tukar poin di keranjang (modul 10). Ditemukan di HP 2026-11-23: mengetuk "Tukar poin" tidak
/// membuka apa pun (tidak ada dialog dan tidak ada pesan), padahal pelanggan punya 17 poin dan
/// aturan poin aktif.
void main() {
  testWidgets('Tukar poin: dialog terbuka, poin diterapkan dan labelnya berubah', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await db.produkDao.upsertProduk(ProdukCompanion.insert(
      id: 'p1',
      tokoId: 'toko-default',
      nama: 'Kopi Hitam',
      tipe: ProdukTipe.barang,
      hargaJual: const Value(50000),
      createdAt: 0,
      updatedAt: 0,
    ));
    await db.stokDao.catatMutasi(
      tokoId: 'toko-default',
      outletId: 'outlet-default',
      produkId: 'p1',
      jenis: MutasiJenis.stokAwal,
      qty: 10,
    );
    await seedMetodeBayarUjiCoba(db);
    await db.fiturDao.simpanStatusFitur(
      tokoId: 'toko-default',
      paket: 'Pro',
      kodeFiturAktif: const ['poin_loyalitas'],
      batasPerKode: const {},
      updatedAt: 0,
    );
    await db.into(db.pelanggan).insert(PelangganCompanion.insert(
      id: 'pel-1',
      tokoId: 'toko-default',
      nama: 'Uji Pelanggan',
      poin: const Value(17),
      createdAt: 0,
      updatedAt: 0,
    ));
    await db.pelangganDao.upsertAturanPoin(AturanPoinCompanion.insert(
      tokoId: 'toko-default',
      nominalPerPoin: const Value(1000),
      nilaiTukarPoin: const Value(100),
      minTukarPoin: const Value(5),
      createdAt: 0,
      updatedAt: 0,
    ));

    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: overridesSudahLogin(db),
      child: const AppsPosApp(),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Buka Shift'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('bukaShiftForm.modalAwal')), '0');
    await tester.tap(find.text('Mulai shift'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kopi Hitam'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lihat keranjang'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Pilih'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Uji Pelanggan'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Tukar poin'));
    // Aturan poin dibaca dari basis data (async nyata), jadi beri waktu nyata sebelum memompa frame.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('keranjangForm.poinDitukar')), findsOneWidget, reason: 'dialog tukar poin harus terbuka');
    expect(find.text('Saldo poin Uji Pelanggan: 17'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('keranjangForm.poinDitukar')), '10');
    await tester.tap(find.byKey(const Key('keranjangForm.terapkanPoin')));
    await tester.pumpAndSettle();

    expect(find.text('Tukar 10 poin'), findsWidgets, reason: 'tombol berubah dan ringkasan harga memuat baris tukar poin');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
