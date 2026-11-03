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
  testWidgets('buka shift -> tambah produk -> bayar QRIS -> struk -> stok terdebit',
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

    await tester.tap(find.text('Buka Shift'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('bukaShiftForm.modalAwal')), '50000');
    await tester.tap(find.text('Mulai shift'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Kopi Hitam'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Lihat keranjang'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bayar Rp15.000'));
    await tester.pumpAndSettle();

    // Sengaja TIDAK pakai pumpAndSettle begitu BayarQrisPage ter-mount -
    // halaman ini punya Timer.periodic (hitung mundur) yang terus menjadwalkan
    // frame baru setiap 1 detik simulasi, jadi pumpAndSettle tidak akan
    // pernah selesai (menunggu "tidak ada frame terjadwal").
    await tester.tap(find.text('QRIS\n(cek manual)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('QRIS statis (cek manual)'), findsOneWidget);

    // Tombol "Cek status" baru aktif setelah kasir menandai konfirmasi
    // manual (tahap 4 bagian A.1 - belum ada gateway sungguhan).
    final checkboxKonfirmasi = find.byKey(const Key('bayarQrisPage.konfirmasiCekDana'));
    await tester.ensureVisible(checkboxKonfirmasi);
    await tester.pump();
    await tester.tap(checkboxKonfirmasi);
    await tester.pump();

    final tombolCekStatus = find.widgetWithText(FilledButton, 'Cek status');
    await tester.ensureVisible(tombolCekStatus);
    await tester.pump();
    await tester.tap(tombolCekStatus);
    // Beberapa pump kecil (bukan pumpAndSettle - lihat komentar di atas)
    // untuk memberi waktu chain async checkout() + animasi pushReplacement
    // selesai satu per satu.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('Pembayaran berhasil'), findsOneWidget);

    final stokRow = await (db.select(db.stok)
          ..where((t) => t.outletId.equals('outlet-default') & t.produkId.equals('p1')))
        .getSingle();
    expect(stokRow.jumlah, 10 - 1);

    final transaksiRows = await db.select(db.transaksi).get();
    expect(transaksiRows, hasLength(1));
    expect(transaksiRows.single.total, 15000);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
