import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/features/produk/data/local/tables/produk_table.dart';
import 'package:apps_pos/features/stok/data/local/tables/mutasi_stok_table.dart';
import 'package:apps_pos/main.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

/// IMOGI no. 13: metode kartu yang diatur "wajib no. referensi" menolak
/// pembayaran tanpa no. referensi dan 4 digit akhir, dan menerimanya bila lengkap.
void main() {
  testWidgets('kartu wajib referensi: ditolak bila kosong, diterima bila lengkap', (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

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
    await db.metodeBayarDao.ubahWajibReferensi('metode-kartu-uji', true, now: 1);

    await tester.pumpWidget(ProviderScope(overrides: overridesSudahLogin(db), child: const AppsPosApp()));
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

    await tester.tap(find.text('Kartu').first);
    await tester.pumpAndSettle();
    expect(find.text('Nomor referensi (wajib)'), findsOneWidget);
    expect(find.text('4 digit akhir kartu (wajib)'), findsOneWidget);

    // Kosong -> ditolak, tidak ada transaksi.
    await tester.tap(find.byKey(const Key('bayarForm.selesaikan')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('No. referensi wajib diisi untuk metode ini'), findsOneWidget);
    expect(await db.select(db.transaksi).get(), isEmpty);

    // Referensi lengkap tetapi jenis kartu belum dipilih -> ditolak.
    await tester.enterText(find.byKey(const Key('bayarForm.nomorReferensi')), 'APP-778');
    await tester.enterText(find.byKey(const Key('bayarForm.empatDigitAkhir')), '9876');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('bayarForm.selesaikan')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Pilih jenis kartu (debit atau kredit)'), findsOneWidget);
    expect(await db.select(db.transaksi).get(), isEmpty);

    // Pilih Kredit -> diterima.
    await tester.tap(find.byKey(const Key('bayarForm.jenisKartu.kredit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('bayarForm.selesaikan')));
    await tester.pumpAndSettle();

    expect(find.text('Pembayaran berhasil'), findsOneWidget);
    final pembayaran = await db.select(db.pembayaran).get();
    expect(pembayaran, hasLength(1));
    expect(pembayaran.single.refGateway, 'APP-778');
    expect(pembayaran.single.payloadGateway, contains('"jenis_kartu":"kredit"'));

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
