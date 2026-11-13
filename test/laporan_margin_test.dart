import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/core/harga/kalkulator.dart' as k;
import 'package:apps_pos/features/laporan/data/laporan_repository.dart';
import 'package:apps_pos/features/laporan/domain/ringkasan_laporan.dart';
import 'package:apps_pos/features/laporan/presentation/pages/laporan_page.dart';
import 'package:apps_pos/features/produk/data/local/tables/produk_table.dart';
import 'package:apps_pos/features/transaksi/data/transaksi_repository.dart';
import 'package:apps_pos/features/transaksi/domain/item_keranjang.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

k.HasilKalkulasi _hitung(List<ItemKeranjang> items) => k.hitung(
      k.TransaksiInput(items: [
        for (final i in items)
          k.ItemInput(
              produkId: i.produkId, varianId: null, namaProduk: i.namaProduk, qty: i.qty, hargaJual: i.hargaSatuan),
      ]),
    );

void main() {
  group('hitungMarginProduk (fungsi murni)', () {
    test('menjumlahkan per produk dan mengurutkan laba terbesar lebih dulu', () {
      final hasil = hitungMarginProduk(const [
        BarisItemMargin(nama: 'Kopi', qty: 2, omzet: 36000, hpp: 14000),
        BarisItemMargin(nama: 'Roti', qty: 1, omzet: 15000, hpp: 9000),
        BarisItemMargin(nama: 'Kopi', qty: 1, omzet: 18000, hpp: 7000),
      ]);
      expect(hasil.map((m) => m.namaProduk), ['Kopi', 'Roti']);
      final kopi = hasil.first;
      expect(kopi.qty, 3);
      expect(kopi.omzet, 54000);
      expect(kopi.hpp, 21000);
      expect(kopi.laba, 33000);
      expect(kopi.marginPersen, closeTo(61.11, 0.01));
      expect(hasil.last.marginPersen, closeTo(40, 0.01));
    });

    test('HPP kosong ditandai tersendiri, bukan margin 100 persen', () {
      final m = hitungMarginProduk(const [BarisItemMargin(nama: 'Air', qty: 1, omzet: 3000, hpp: 0)]).single;
      expect(m.hppKosong, isTrue);
      expect(m.marginPersen, isNull);
      expect(m.laba, 3000);
    });

    test('daftar kosong dan omzet nol tidak membagi dengan nol', () {
      expect(hitungMarginProduk(const []), isEmpty);
      final m = hitungMarginProduk(const [BarisItemMargin(nama: 'Gratis', qty: 1, omzet: 0, hpp: 500)]).single;
      expect(m.marginPersen, isNull);
      expect(m.hppKosong, isFalse);
    });
  });

  group('snapshot HPP saat checkout', () {
    late AppDatabase db;
    late TransaksiRepository repo;
    late LaporanRepository laporan;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      repo = TransaksiRepository(db.transaksiDao, db.stokDao, db.produkDao);
      laporan = LaporanRepository(db.transaksiDao);
      await db.produkDao.upsertProduk(ProdukCompanion.insert(
        id: 'kopi',
        tokoId: 't1',
        nama: 'Kopi Susu',
        tipe: ProdukTipe.barang,
        hargaJual: const Value(18000),
        hpp: const Value(7000),
        createdAt: 0,
        updatedAt: 0,
      ));
    });

    tearDown(() => db.close());

    Future<void> jual(double qty) async {
      final items = [ItemKeranjang(produkId: 'kopi', namaProduk: 'Kopi Susu', hargaSatuan: 18000, qty: qty, lacakStok: false)];
      await repo.checkout(
        tokoId: 't1',
        outletId: 'o1',
        shiftId: 's1',
        penggunaId: 'u1',
        metodeBayarId: 'metode-tunai-default',
        items: items,
        hasil: _hitung(items),
        totalBayar: (18000 * qty).round(),
      );
    }

    test('item transaksi menyimpan HPP produk saat itu, laba kotor dan margin laporan benar', () async {
      await jual(3);
      final row = (await db.select(db.itemTransaksi).get()).single;
      expect(row.hppSatuan, 7000);

      final r = await laporan.ringkasan('o1', PeriodeLaporan.hariIni);
      expect(r.penjualanBersih, 54000);
      expect(r.labaKotor, 3 * (18000 - 7000));
      final m = r.marginProduk.single;
      expect(m.namaProduk, 'Kopi Susu');
      expect(m.qty, 3);
      expect(m.omzet, 54000);
      expect(m.hpp, 21000);
      expect(m.laba, 33000);
    });

    test('mengubah HPP produk sesudahnya tidak mengubah transaksi lama, transaksi baru memakai HPP baru', () async {
      await jual(1);
      await db.produkDao.upsertProduk(ProdukCompanion.insert(
        id: 'kopi',
        tokoId: 't1',
        nama: 'Kopi Susu',
        tipe: ProdukTipe.barang,
        hargaJual: const Value(18000),
        hpp: const Value(9000),
        createdAt: 0,
        updatedAt: 1,
      ));
      await jual(1);

      final hpp = [for (final r in await db.select(db.itemTransaksi).get()) r.hppSatuan]..sort();
      expect(hpp, [7000, 9000]);
      final r = await laporan.ringkasan('o1', PeriodeLaporan.hariIni);
      expect(r.marginProduk.single.hpp, 16000);
    });

    test('produk tanpa HPP tetap tersimpan 0 dan ditandai HPP kosong di laporan', () async {
      await db.produkDao.upsertProduk(ProdukCompanion.insert(
        id: 'air',
        tokoId: 't1',
        nama: 'Air Putih',
        tipe: ProdukTipe.barang,
        hargaJual: const Value(3000),
        createdAt: 0,
        updatedAt: 0,
      ));
      final items = [const ItemKeranjang(produkId: 'air', namaProduk: 'Air Putih', hargaSatuan: 3000, qty: 1, lacakStok: false)];
      await repo.checkout(
        tokoId: 't1', outletId: 'o1', shiftId: 's1', penggunaId: 'u1', metodeBayarId: 'metode-tunai-default',
        items: items, hasil: _hitung(items), totalBayar: 3000,
      );
      final m = (await laporan.ringkasan('o1', PeriodeLaporan.hariIni)).marginProduk.single;
      expect(m.hppKosong, isTrue);
    });
  });

  testWidgets('halaman Laporan menampilkan kartu HPP & margin dengan penanda margin rendah', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = TransaksiRepository(db.transaksiDao, db.stokDao, db.produkDao);
    await db.fiturDao.simpanStatusFitur(
      tokoId: 'toko-default',
      paket: 'Bisnis',
      kodeFiturAktif: const ['product_margin'],
      batasPerKode: const {},
      updatedAt: 0,
    );
    Future<void> produk(String id, String nama, int jual, int hpp) => db.produkDao.upsertProduk(ProdukCompanion.insert(
          id: id,
          tokoId: 'toko-default',
          nama: nama,
          tipe: ProdukTipe.barang,
          hargaJual: Value(jual),
          hpp: Value(hpp),
          createdAt: 0,
          updatedAt: 0,
        ));
    await produk('kopi', 'Kopi Susu', 18000, 7000); // margin 61%
    await produk('teh', 'Teh Murah', 10000, 7000); // margin 30%: di bawah batas 50
    await produk('air', 'Air Putih', 3000, 0); // HPP kosong
    for (final p in [('kopi', 'Kopi Susu', 18000), ('teh', 'Teh Murah', 10000), ('air', 'Air Putih', 3000)]) {
      final items = [ItemKeranjang(produkId: p.$1, namaProduk: p.$2, hargaSatuan: p.$3, qty: 1, lacakStok: false)];
      await repo.checkout(
        tokoId: 'toko-default', outletId: 'outlet-default', shiftId: 's1', penggunaId: 'u1',
        metodeBayarId: 'metode-tunai-default', items: items, hasil: _hitung(items), totalBayar: p.$3,
      );
    }

    tester.view.physicalSize = const Size(900, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: overridesSudahLogin(db),
      child: const MaterialApp(home: LaporanPage()),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('laporan.marginProduk')), findsOneWidget);
    expect(find.text('HPP & margin per produk'), findsOneWidget);
    expect(find.text('Margin 61%'), findsOneWidget);
    expect(find.text('Margin 30%'), findsOneWidget);
    expect(find.text('HPP belum diisi'), findsOneWidget);
    expect(find.textContaining('Batas margin 50%'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
