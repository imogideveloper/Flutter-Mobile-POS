import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/core/widgets/app_toast.dart';
import 'package:apps_pos/features/produk/data/local/tables/produk_table.dart' hide Produk;
import 'package:apps_pos/features/stok/data/local/tables/mutasi_stok_table.dart' show MutasiJenis;
import 'package:apps_pos/main.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

/// Toast "Stok menipis" sesudah checkout - tadinya SnackBar polos bawaan
/// Flutter, sekarang pakai AppToast kustom (core/widgets/app_toast.dart)
/// supaya lebih menonjol & konsisten dgn design system (lihat
/// struk_page.dart._ingatkanStokMenipis).
void main() {
  testWidgets('checkout yang bikin stok produk <= batas minimum menampilkan toast "Stok menipis"',
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
    // Stok awal 2, batas minimum 5 - sudah menipis SEBELUM transaksi pun,
    // jadi begitu dijual (sisa 1) pasti tetap <= batas minimum.
    await db.stokDao.catatMutasi(
      tokoId: 'toko-default',
      outletId: 'outlet-default',
      produkId: 'p1',
      jenis: MutasiJenis.stokAwal,
      qty: 2,
      batasMinimum: 5,
    );
    await seedMetodeBayarUjiCoba(db);

    await tester.pumpWidget(ProviderScope(
      overrides: overridesSudahLogin(db),
      child: const AppsPosApp(),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Buka Shift'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('bukaShiftForm.modalAwal')), '50000');
    await tester.tap(find.text('Mulai shift'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Kopi Hitam'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Lihat keranjang'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bayar Rp15.000'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('bayarForm.uangDiterima')), '20000');
    await tester.drag(find.byKey(const Key('bayarForm.scrollView')), const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Selesaikan pembayaran'));
    await tester.pumpAndSettle();

    expect(find.text('Pembayaran berhasil'), findsOneWidget);

    // Toast dipicu dari addPostFrameCallback - beri jeda spt test flow lain.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(find.text('Stok menipis'), findsOneWidget);
    expect(find.text('Kopi Hitam'), findsWidgets); // di toast + grid produk di belakangnya

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('showAppToast menampilkan judul, pesan, lalu hilang sendiri', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () => showAppToast(
                context,
                title: 'Judul toast',
                message: 'Pesan toast',
                variant: ToastVariant.warning,
                duration: const Duration(milliseconds: 200),
              ),
              child: const Text('Tampilkan'),
            ),
          ),
        ),
      ),
    ));

    // pump() manual bertahap KECIL-KECIL (BUKAN pumpAndSettle, BUKAN satu
    // lompatan besar) - ditemukan sambil nulis test ini: pump(Duration)
    // sekali lompat besar memproses SEMUA Timer yang jatuh tempo dalam
    // jendela itu (termasuk Timer auto-tutup) SEBELUM frame/ticker baru
    // sempat jalan - jadi animasi masuk belum pernah bernilai > 0 saat
    // timer auto-tutup 200ms ikut kepicu di lompatan yang sama, toast
    // langsung reverse() dari value=0 dan ke-remove tanpa pernah
    // ter-render. Di app sungguhan ini tidak masalah (banyak frame
    // sungguhan terjadi tiap saat), murni artefak cara pump() simulasi
    // waktu - step kecil memberi ticker kesempatan jalan di antaranya.
    await tester.tap(find.text('Tampilkan'));
    await tester.pump(); // frame pertama - overlay terpasang
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('Judul toast'), findsOneWidget);
    expect(find.text('Pesan toast'), findsOneWidget);

    // Lewati durasi auto-tutup (200ms) + animasi keluar (160ms) - tetap
    // step kecil spy reverse-nya ikut ter-render dulu sebelum entry
    // benar2 di-remove.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('Judul toast'), findsNothing);
  });
}
