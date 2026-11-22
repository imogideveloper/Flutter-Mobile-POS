import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/core/harga/kalkulator.dart' as k;
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

/// Kartu ringkasan Laporan: penjualan bersih sebagai angka utama, pajak/service dan total penerimaan terpisah,
/// semua kolom sejajar (tiga kolom sama lebar).
void main() {
  testWidgets('kartu ringkasan memuat tiga angka berlabel jelas dan kolomnya sejajar', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = TransaksiRepository(db.transaksiDao, db.stokDao, db.produkDao);
    await db.produkDao.upsertProduk(ProdukCompanion.insert(
      id: 'kopi',
      tokoId: 'toko-default',
      nama: 'Kopi Susu',
      tipe: ProdukTipe.barang,
      hargaJual: const Value(18000),
      hpp: const Value(7000),
      createdAt: 0,
      updatedAt: 0,
    ));
    final items = [
      const ItemKeranjang(produkId: 'kopi', namaProduk: 'Kopi Susu', hargaSatuan: 18000, qty: 1, lacakStok: false),
    ];
    await repo.checkout(
      tokoId: 'toko-default',
      outletId: 'outlet-default',
      shiftId: 's1',
      penggunaId: 'u1',
      metodeBayarId: 'metode-tunai-default',
      items: items,
      hasil: k.hitung(k.TransaksiInput(
        items: [k.ItemInput(produkId: 'kopi', varianId: null, namaProduk: 'Kopi Susu', qty: 1, hargaJual: 18000)],
        serviceDefault: const [
          k.PajakInput(id: 'svc', nama: 'Service Charge', persen: 5, termasukHarga: false, urutan: 0),
        ],
        pajakDefault: const [
          k.PajakInput(id: 'pb1', nama: 'PB1', persen: 10, termasukHarga: false, urutan: 1),
        ],
      )),
      totalBayar: 20790,
    );

    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: overridesSudahLogin(db),
      child: const MaterialApp(home: LaporanPage()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Penjualan bersih'), findsOneWidget);
    expect((tester.widget(find.byKey(const Key('laporan.penjualanBersih'))) as Text).data, 'Rp18.000');
    expect(find.text('Tanpa pajak dan service, setelah diskon dan refund'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('laporan.pajakService')), matching: find.text('Rp2.790')),
        findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('laporan.totalPenerimaan')), matching: find.text('Rp20.790')),
        findsOneWidget);

    // Kolom sejajar: baris kedua memakai tiga kolom yang sama lebar dengan baris pertama.
    double kiri(String teks) => tester.getTopLeft(find.text(teks).first).dx;
    expect(kiri('Pajak & service'), kiri('Laba kotor'));
    expect(kiri('Total penerimaan'), kiri('Transaksi'));
    expect(kiri('Laba kotor'), lessThan(kiri('Transaksi')));
    expect(kiri('Transaksi'), lessThan(kiri('Rata-rata')));

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
