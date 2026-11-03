import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/features/produk/data/local/tables/produk_table.dart'
    hide Produk;
import 'package:apps_pos/features/stok/data/local/tables/mutasi_stok_table.dart'
    show MutasiJenis;
import 'package:apps_pos/main.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

void main() {
  testWidgets('buka shift -> tambah produk ke keranjang -> bayar -> struk -> stok terdebit',
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
    await db.stokDao.catatMutasi(
      tokoId: 'toko-default',
      outletId: 'outlet-default',
      produkId: 'p1',
      jenis: MutasiJenis.stokAwal,
      qty: 10,
    );
    await seedMetodeBayarUjiCoba(db);

    await tester.pumpWidget(ProviderScope(
      overrides: overridesSudahLogin(db),
      child: const AppsPosApp(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Buka shift dulu sebelum mulai transaksi'), findsOneWidget);
    await tester.tap(find.text('Buka Shift'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('bukaShiftForm.modalAwal')), '50000');
    await tester.tap(find.text('Mulai shift'));
    await tester.pumpAndSettle();

    expect(find.text('Kopi Hitam'), findsOneWidget);

    await tester.tap(find.text('Kopi Hitam'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kopi Hitam'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Lihat keranjang'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bayar Rp30.000'));
    await tester.pumpAndSettle();

    expect(find.text('Total tagihan', skipOffstage: false), findsWidgets);

    await tester.enterText(
        find.byKey(const Key('bayarForm.uangDiterima')), '40000');
    // Form bayar jadi lebih panjang sejak ada opsi Kasbon (tahap 3b-1) -
    // scroll dulu supaya tombol submit yang di bawah tidak kena clip area
    // SingleChildScrollView (pola sama dgn form panjang lain, lihat catatan
    // eksekusi di plan).
    await tester.drag(
        find.byKey(const Key('bayarForm.scrollView')), const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Selesaikan pembayaran'));
    await tester.pumpAndSettle();

    expect(find.text('Pembayaran berhasil'), findsOneWidget);
    expect(find.text('Rp10.000'), findsWidgets); // kembalian (muncul di header + rincian struk)

    // Beri jeda tambahan utk postFrameCallback StrukPage._simpanSnapshotStruk
    // (temuan A.2) - async-nya lanjut setelah pumpAndSettle di atas selesai.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Transaksi baru'));
    await tester.pumpAndSettle();

    expect(find.text('Buka shift dulu sebelum mulai transaksi'), findsNothing);
    expect(find.text('Kopi Hitam'), findsOneWidget);

    final stokRow = await (db.select(db.stok)
          ..where((t) => t.outletId.equals('outlet-default') & t.produkId.equals('p1')))
        .getSingle();
    expect(stokRow.jumlah, 10 - 2);

    final transaksiRows = await db.select(db.transaksi).get();
    expect(transaksiRows, hasLength(1));
    expect(transaksiRows.single.total, 30000);
    // Temuan A.2 (tahap 5) - StrukPage wajib menyimpan snapshot struk tepat
    // setelah checkout (via addPostFrameCallback), terlepas dari apakah
    // kasir benar2 menekan tombol cetak atau tidak.
    expect(transaksiRows.single.snapshotStruk != null, true);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
