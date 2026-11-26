import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/core/providers/session_provider.dart';
import 'package:apps_pos/features/produk/data/local/tables/produk_table.dart' hide Produk;
import 'package:apps_pos/features/transaksi/presentation/pages/kasir_page.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

/// Permintaan lead 2026-11-26: foto produk di Kasir terlalu kecil, harus 1:1. Kartu juga tidak boleh terpotong
/// (nama 2 baris, harga, stok, dan tombol jumlah setelah produk dipilih).
void main() {
  test('2 kolom di HP, lebih banyak di tablet; tinggi kartu ikut lebar kartu (foto persegi)', () {
    expect(kolomGridKasir(360), 2);
    expect(kolomGridKasir(412), 2);
    expect(kolomGridKasir(800), greaterThan(2));
    final hp = tinggiKartuProdukKasir(lebarGrid: 360);
    final hpLebar = tinggiKartuProdukKasir(lebarGrid: 412);
    expect(hpLebar - hp, closeTo((412 - 360) / 2, 0.01), reason: 'tinggi ikut lebar kartu, jadi foto tetap persegi');
  });

  testWidgets('foto produk di Kasir persegi dan kartu tidak terpotong di HP 360x800', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.produkDao.upsertProduk(ProdukCompanion.insert(
      id: 'p1',
      tokoId: tokoIdPlaceholder,
      nama: 'Es Kopi Susu Gula Aren Ukuran Besar Sekali',
      tipe: ProdukTipe.barang,
      hargaJual: const Value(28000),
      createdAt: 0,
      updatedAt: 0,
    ));
    await db.shiftDao.bukaShift(
      id: 'sh1',
      tokoId: tokoIdPlaceholder,
      outletId: outletIdPlaceholder,
      penggunaId: 'pengguna-1',
      modalAwal: 0,
    );

    await tester.pumpWidget(ProviderScope(
      overrides: overridesSudahLogin(db),
      child: const MaterialApp(home: KasirPage()),
    ));
    await tester.pumpAndSettle();

    final foto = find.descendant(of: find.byType(GridView), matching: find.byType(ClipRRect)).first;
    final ukuran = tester.getSize(foto);
    expect(ukuran.width, closeTo(ukuran.height, 0.5), reason: 'foto 1:1');
    expect(ukuran.width, greaterThan(140), reason: 'foto lebih besar dari sebelumnya (dulu tinggi = lebar / 1,3)');

    await tester.tap(find.textContaining('Es Kopi Susu'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'kartu dengan tombol jumlah tidak terpotong');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
