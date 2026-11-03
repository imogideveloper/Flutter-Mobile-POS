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

/// F3.A - bayar satu transaksi pakai 2 metode sekaligus (tunai+kartu),
/// jumlah keduanya WAJIB persis sama dgn total; pastikan 2 baris
/// Pembayaran tersimpan lokal, bukan cuma 1.
void main() {
  testWidgets('bayar campur tunai+kartu - dua baris pembayaran tersimpan',
      (tester) async {
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
    await tester.tap(find.text('Bayar Rp50.000'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('bayarForm.toggleSplit')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('bayarForm.split.a.metode')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tunai').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('bayarForm.split.a.jumlah')), '20000');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('bayarForm.split.b.metode')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kartu').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('bayarForm.split.b.jumlah')), '30000');
    await tester.pumpAndSettle();

    await tester.drag(
        find.byKey(const Key('bayarForm.scrollView')), const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('bayarForm.selesaikan')));
    await tester.pumpAndSettle();

    expect(find.text('Pembayaran berhasil'), findsOneWidget);

    final transaksiRows = await db.select(db.transaksi).get();
    expect(transaksiRows, hasLength(1));
    expect(transaksiRows.single.total, 50000);
    expect(transaksiRows.single.totalBayar, 50000);

    final pembayaranRows = await (db.select(db.pembayaran)
          ..where((t) => t.transaksiId.equals(transaksiRows.single.id)))
        .get();
    expect(pembayaranRows, hasLength(2));
    final jumlahByMetode = {for (final p in pembayaranRows) p.metodeBayarId: p.jumlah};
    expect(jumlahByMetode['metode-tunai-uji'], 20000);
    expect(jumlahByMetode['metode-kartu-uji'], 30000);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
