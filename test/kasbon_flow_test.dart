import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/features/produk/data/local/tables/produk_table.dart'
    hide Produk;
import 'package:apps_pos/features/stok/data/local/tables/mutasi_stok_table.dart'
    show MutasiJenis;
import 'package:apps_pos/features/transaksi/data/local/tables/pembayaran_table.dart';
import 'package:apps_pos/features/transaksi/data/local/tables/transaksi_table.dart';
import 'package:apps_pos/main.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

/// Tahap 3b-1: alur utuh keranjang -> bayar kasbon dengan DP -> drift ->
/// struk - pastikan total/dibayar/sisa yang sama persis di layar bayar,
/// drift, dan struk (sama tuntutan dgn kasir_flow_test.dart non-kasbon).
void main() {
  testWidgets(
      'buka shift -> tambah produk -> bayar kasbon dgn DP -> struk -> sisa tagihan konsisten',
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
    await db.pelangganDao.upsertPelanggan(PelangganCompanion.insert(
      id: 'pelanggan-1',
      tokoId: 'toko-default',
      nama: 'Budi Santoso',
      createdAt: 0,
      updatedAt: 0,
    ));
    // Tanpa ini FiturTerkunci mengunci 'kasbon'/'dp_kasbon' (cache gating
    // kosong = belum pernah sync) - lihat FeatureGate/FiturTerkunci.
    await db.fiturDao.simpanStatusFitur(
      tokoId: 'toko-default',
      paket: 'Bisnis',
      kodeFiturAktif: const ['kasbon', 'dp_kasbon'],
      batasPerKode: const {},
      updatedAt: 0,
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
    await tester.tap(find.text('Kopi Hitam'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Lihat keranjang'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bayar Rp30.000'));
    await tester.pumpAndSettle();

    await tester.drag(
        find.byKey(const Key('bayarForm.scrollView')), const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('bayarForm.kasbon')));
    await tester.pumpAndSettle();

    expect(find.text('Kasbon'), findsOneWidget);

    await tester.tap(find.byKey(const Key('bayarKasbonForm.pelanggan')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Budi Santoso'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('bayarKasbonForm.dp')), '10000');
    await tester.pumpAndSettle();

    expect(find.text('Rp10.000'), findsWidgets); // "Dibayar sekarang"
    expect(find.text('Rp20.000'), findsWidgets); // "Sisa tagihan"

    await tester.drag(find.byKey(const Key('bayarKasbonForm.scrollView')),
        const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('bayarKasbonForm.simpan')));
    await tester.pumpAndSettle();

    expect(find.text('Transaksi tercatat (kasbon)'), findsOneWidget);
    expect(find.text('Rp20.000'), findsWidgets); // sisa tagihan di header+struk

    final transaksiRows = await db.select(db.transaksi).get();
    expect(transaksiRows, hasLength(1));
    final transaksi = transaksiRows.single;
    expect(transaksi.total, 30000);
    expect(transaksi.totalBayar, 10000);
    expect(transaksi.sisaTagihan, 20000);
    expect(transaksi.statusBayar, StatusBayarTransaksi.sebagian);
    expect(transaksi.jatuhTempo, isNotNull);
    expect(transaksi.pelangganId, 'pelanggan-1');

    final pembayaranRows = await db.select(db.pembayaran).get();
    expect(pembayaranRows, hasLength(1));
    expect(pembayaranRows.single.jumlah, 10000);
    expect(pembayaranRows.single.jenis, PembayaranJenis.dp);
    expect(pembayaranRows.single.disinkronPada, isNotNull);

    final stokRow = await (db.select(db.stok)
          ..where((t) => t.outletId.equals('outlet-default') & t.produkId.equals('p1')))
        .getSingle();
    expect(stokRow.jumlah, 10 - 2);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
