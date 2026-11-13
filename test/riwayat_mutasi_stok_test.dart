import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/features/produk/data/local/tables/produk_table.dart';
import 'package:apps_pos/features/stok/data/local/tables/mutasi_stok_table.dart' show MutasiJenis;
import 'package:apps_pos/features/stok/domain/mutasi_item.dart';
import 'package:apps_pos/features/stok/domain/riwayat_mutasi.dart';
import 'package:apps_pos/features/stok/presentation/pages/riwayat_mutasi_stok_page.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'test_helpers.dart';

MutasiItem _m(String id, MutasiJenis jenis, double qty, {double? saldo}) =>
    MutasiItem(id: id, produkNama: 'Kopi', jenis: jenis, qty: qty, catatan: null, createdAt: 1, saldoSetelah: saldo);

void main() {
  group('logika riwayat mutasi', () {
    final data = [
      _m('1', MutasiJenis.stokAwal, 10, saldo: 10),
      _m('2', MutasiJenis.penjualan, -3, saldo: 7),
      _m('3', MutasiJenis.pembelian, 5.5, saldo: 12.5),
      _m('4', MutasiJenis.opname, -1.5, saldo: 11),
    ];

    test('saringMutasi memisahkan masuk dan keluar', () {
      expect(saringMutasi(data, FilterMutasi.semua).length, 4);
      expect(saringMutasi(data, FilterMutasi.masuk).map((m) => m.id), ['1', '3']);
      expect(saringMutasi(data, FilterMutasi.keluar).map((m) => m.id), ['2', '4']);
    });

    test('ringkasMutasi menjumlahkan masuk dan keluar (keluar sebagai angka positif)', () {
      final r = ringkasMutasi(data);
      expect(r.masuk, 15.5);
      expect(r.keluar, 4.5);
      expect(ringkasMutasi(const []), (masuk: 0.0, keluar: 0.0));
    });

    test('labelMutasi memberi nama untuk setiap jenis', () {
      for (final j in MutasiJenis.values) {
        expect(labelMutasi(j), isNotEmpty);
      }
      expect(labelMutasi(MutasiJenis.voidTransaksi), 'Void');
      expect(labelMutasi(MutasiJenis.transferMasuk), 'Transfer masuk');
    });
  });

  testWidgets('halaman riwayat menampilkan mutasi produk itu saja, saldo, total, dan filter', (tester) async {
    await initializeDateFormatting('id_ID');
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    Future<void> produk(String id, String nama) => db.produkDao.upsertProduk(ProdukCompanion.insert(
          id: id,
          tokoId: 'toko-default',
          nama: nama,
          tipe: ProdukTipe.barang,
          createdAt: 0,
          updatedAt: 0,
        ));
    Future<void> mutasi(String produkId, MutasiJenis jenis, double qty, {String? catatan}) => db.stokDao.catatMutasi(
          tokoId: 'toko-default',
          outletId: 'outlet-default',
          produkId: produkId,
          jenis: jenis,
          qty: qty,
          catatan: catatan,
        );

    await produk('kopi', 'Kopi Susu');
    await produk('teh', 'Teh Tarik');
    await mutasi('kopi', MutasiJenis.stokAwal, 10);
    await mutasi('kopi', MutasiJenis.penjualan, -3);
    await mutasi('kopi', MutasiJenis.pembelian, 5, catatan: 'Beli dari pasar');
    await mutasi('teh', MutasiJenis.stokAwal, 99); // produk lain: tidak boleh tampil

    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: overridesSudahLogin(db),
      child: const MaterialApp(home: RiwayatMutasiStokPage(produkId: 'kopi', produkNama: 'Kopi Susu')),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Stok awal'), findsOneWidget);
    expect(find.text('Penjualan'), findsOneWidget);
    expect(find.text('Pembelian'), findsOneWidget);
    expect(find.text('Beli dari pasar'), findsOneWidget);
    expect(find.text('+99'), findsNothing, reason: 'mutasi produk lain tidak ikut');

    String teks(String kunci) => tester.widget<Text>(find.byKey(Key(kunci))).data!;
    expect(teks('riwayatStok.masuk'), '+15');
    expect(teks('riwayatStok.keluar'), '-3');
    expect(teks('riwayatStok.saldo'), '12');
    expect(find.text('Saldo 12'), findsOneWidget, reason: 'saldo setelah mutasi terakhir');

    await tester.tap(find.byKey(const Key('riwayatStok.filter.keluar')));
    await tester.pumpAndSettle();
    expect(find.text('Penjualan'), findsOneWidget);
    expect(find.text('Pembelian'), findsNothing);
    expect(find.text('Stok awal'), findsNothing);

    await tester.tap(find.byKey(const Key('riwayatStok.filter.masuk')));
    await tester.pumpAndSettle();
    expect(find.text('Penjualan'), findsNothing);
    expect(find.text('Pembelian'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('produk tanpa mutasi menampilkan pesan kosong', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(ProviderScope(
      overrides: overridesSudahLogin(db),
      child: const MaterialApp(home: RiwayatMutasiStokPage(produkId: 'tidak-ada', produkNama: 'X')),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Belum ada mutasi untuk produk ini'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
