import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/features/produk/data/local/tables/produk_table.dart' show ProdukTipe;
import 'package:apps_pos/features/produk/domain/kategori.dart';
import 'package:apps_pos/features/produk/domain/produk.dart';
import 'package:apps_pos/features/transaksi/domain/filter_produk_kasir.dart';
import 'package:apps_pos/main.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

Produk _p(String id, String nama, {String? kategori, String? sku}) => Produk(
      id: id,
      tokoId: 't',
      kategoriId: kategori,
      sku: sku,
      nama: nama,
      tipe: ProdukTipe.barang,
      lacakStok: false,
      punyaVarian: false,
      pakaiResep: false,
      hpp: 0,
      hargaJual: 10000,
      dijual: true,
      aktif: true,
    );

Kategori _k(String id, String nama, int urutan) =>
    Kategori(id: id, tokoId: 't', nama: nama, warna: null, urutan: urutan);

void main() {
  group('saringProdukKasir', () {
    final produk = [
      _p('1', 'Kopi Susu', kategori: 'min', sku: 'KS-1'),
      _p('2', 'Teh Tarik', kategori: 'min'),
      _p('3', 'Roti Bakar', kategori: 'mak'),
      _p('4', 'Air Putih'),
    ];

    test('tanpa filter semua produk tampil, termasuk yang tanpa kategori', () {
      expect(saringProdukKasir(produk).map((p) => p.id), ['1', '2', '3', '4']);
    });

    test('kategori menyaring dan produk tanpa kategori tidak ikut', () {
      expect(saringProdukKasir(produk, kategoriId: 'min').map((p) => p.id), ['1', '2']);
      expect(saringProdukKasir(produk, kategoriId: 'mak').map((p) => p.id), ['3']);
      expect(saringProdukKasir(produk, kategoriId: 'tidak-ada'), isEmpty);
    });

    test('pencarian nama atau SKU digabung dengan kategori', () {
      expect(saringProdukKasir(produk, kataCari: 'teh').map((p) => p.id), ['2']);
      expect(saringProdukKasir(produk, kataCari: 'ks-1').map((p) => p.id), ['1']);
      expect(saringProdukKasir(produk, kataCari: 'teh', kategoriId: 'min').map((p) => p.id), ['2']);
      expect(saringProdukKasir(produk, kataCari: 'teh', kategoriId: 'mak'), isEmpty);
      expect(saringProdukKasir(produk, kataCari: '  KOPI ').map((p) => p.id), ['1'], reason: 'tak peka huruf dan spasi');
    });
  });

  group('kategoriDenganProduk', () {
    test('hanya kategori berisi produk, urut menurut urutan lalu nama', () {
      final kategori = [_k('mak', 'Makanan', 2), _k('kos', 'Snack', 3), _k('min', 'Minuman', 1), _k('abc', 'Aneka', 1)];
      final produk = [_p('1', 'A', kategori: 'min'), _p('2', 'B', kategori: 'mak'), _p('3', 'C', kategori: 'abc')];
      expect(kategoriDenganProduk(kategori, produk).map((k) => k.id), ['abc', 'min', 'mak'], reason: 'Snack kosong tidak tampil');
    });

    test('tidak ada produk berkategori menghasilkan daftar kosong', () {
      expect(kategoriDenganProduk([_k('a', 'A', 0)], [_p('1', 'X')]), isEmpty);
    });
  });

  testWidgets('kasir: tab kategori menyaring tile produk dan digabung dengan pencarian', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    Future<void> kat(String id, String nama, int urutan) => db.produkDao.upsertKategori(
        KategoriCompanion.insert(id: id, tokoId: 'toko-default', nama: nama, urutan: Value(urutan), createdAt: 0, updatedAt: 0));
    Future<void> prod(String id, String nama, String? kategori) => db.produkDao.upsertProduk(ProdukCompanion.insert(
          id: id,
          tokoId: 'toko-default',
          kategoriId: Value(kategori),
          nama: nama,
          tipe: ProdukTipe.barang,
          lacakStok: const Value(false),
          hargaJual: const Value(10000),
          createdAt: 0,
          updatedAt: 0,
        ));

    await kat('min', 'Minuman', 1);
    await kat('mak', 'Makanan', 2);
    await kat('kos', 'Snack', 3); // kosong: tidak boleh muncul
    await prod('p1', 'Kopi Susu', 'min');
    await prod('p2', 'Teh Tarik', 'min');
    await prod('p3', 'Roti Bakar', 'mak');
    await prod('p4', 'Air Putih', null);
    await seedMetodeBayarUjiCoba(db);

    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(overrides: overridesSudahLogin(db), child: const AppsPosApp()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Buka Shift'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('bukaShiftForm.modalAwal')), '50000');
    await tester.tap(find.text('Mulai shift'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('kasir.kategori.semua')), findsOneWidget);
    expect(find.byKey(const Key('kasir.kategori.min')), findsOneWidget);
    expect(find.byKey(const Key('kasir.kategori.mak')), findsOneWidget);
    expect(find.byKey(const Key('kasir.kategori.kos')), findsNothing, reason: 'kategori kosong disembunyikan');
    for (final nama in ['Kopi Susu', 'Teh Tarik', 'Roti Bakar', 'Air Putih']) {
      expect(find.text(nama), findsOneWidget);
    }

    await tester.tap(find.byKey(const Key('kasir.kategori.mak')));
    await tester.pumpAndSettle();
    expect(find.text('Roti Bakar'), findsOneWidget);
    expect(find.text('Kopi Susu'), findsNothing);
    expect(find.text('Air Putih'), findsNothing);

    await tester.tap(find.byKey(const Key('kasir.kategori.min')));
    await tester.pumpAndSettle();
    expect(find.text('Kopi Susu'), findsOneWidget);
    expect(find.text('Teh Tarik'), findsOneWidget);
    expect(find.text('Roti Bakar'), findsNothing);

    await tester.enterText(find.byType(TextField).first, 'teh');
    await tester.pumpAndSettle();
    expect(find.text('Teh Tarik'), findsOneWidget);
    expect(find.text('Kopi Susu'), findsNothing);

    await tester.enterText(find.byType(TextField).first, '');
    await tester.tap(find.byKey(const Key('kasir.kategori.semua')));
    await tester.pumpAndSettle();
    expect(find.text('Air Putih'), findsOneWidget);
    expect(find.text('Roti Bakar'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
