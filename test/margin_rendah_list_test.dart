import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/features/produk/data/local/tables/produk_table.dart';
import 'package:apps_pos/features/produk/presentation/pages/produk_list_page.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> produk(String id, String nama, {required int jual, required int hpp}) =>
      db.produkDao.upsertProduk(ProdukCompanion.insert(
        id: id,
        tokoId: 'toko-default',
        nama: nama,
        tipe: ProdukTipe.barang,
        hargaJual: Value(jual),
        hpp: Value(hpp),
        createdAt: 1,
        updatedAt: 1,
      ));

  Future<void> buka(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: overridesSudahLogin(db),
      child: const MaterialApp(home: ProdukListPage()),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> tutup(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  Future<void> semuaProduk() async {
    await produk('a', 'Kopi Susu', jual: 18000, hpp: 7000); // 61%
    await produk('b', 'Teh Murah', jual: 10000, hpp: 7000); // 30%
    await produk('c', 'Air Putih', jual: 3000, hpp: 0); // HPP kosong
  }

  testWidgets('batas bawaan 50 persen: produk margin rendah dan HPP kosong ditandai', (tester) async {
    await semuaProduk();
    await buka(tester);

    expect(find.byKey(const Key('produkList.margin.b')), findsOneWidget);
    expect(find.text('Margin rendah 30% (batas 50%)'), findsOneWidget);
    expect(find.text('HPP belum diisi'), findsOneWidget);
    expect(find.byKey(const Key('produkList.margin.a')), findsNothing, reason: 'margin 61% aman');
    expect(find.text('Margin rendah · 1'), findsOneWidget);
    await tutup(tester);
  });

  testWidgets('filter Margin rendah hanya menampilkan produk bermargin rendah (HPP kosong tidak ikut)', (tester) async {
    await semuaProduk();
    await buka(tester);
    await tester.tap(find.byKey(const Key('produkList.filterMarginRendah')));
    await tester.pumpAndSettle();
    expect(find.text('Teh Murah'), findsOneWidget);
    expect(find.text('Kopi Susu'), findsNothing);
    expect(find.text('Air Putih'), findsNothing);
    await tutup(tester);
  });

  testWidgets('batas diatur per outlet: batas 25 membuat margin 30 persen aman', (tester) async {
    await semuaProduk();
    await db.hargaDao.upsertPengaturanOutlet(PengaturanOutletCompanion.insert(
      outletId: 'outlet-default',
      batasMargin: const Value(25),
      createdAt: 0,
      updatedAt: 0,
    ));
    await buka(tester);
    expect(find.byKey(const Key('produkList.margin.b')), findsNothing);
    expect(find.text('Margin rendah · 0'), findsOneWidget);
    await tutup(tester);
  });

  testWidgets('batas 0 mematikan penanda rendah', (tester) async {
    await semuaProduk();
    await db.hargaDao.upsertPengaturanOutlet(PengaturanOutletCompanion.insert(
      outletId: 'outlet-default',
      batasMargin: const Value(0),
      createdAt: 0,
      updatedAt: 0,
    ));
    await buka(tester);
    expect(find.text('Margin rendah · 0'), findsOneWidget);
    await tutup(tester);
  });
}
