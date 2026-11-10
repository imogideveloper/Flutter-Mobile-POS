import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/core/harga/kalkulator.dart' as k;
import 'package:apps_pos/core/providers/database_provider.dart';
import 'package:apps_pos/features/transaksi/data/transaksi_repository.dart';
import 'package:apps_pos/features/transaksi/domain/item_keranjang.dart';
import 'package:apps_pos/features/transaksi/presentation/pages/transaksi_detail_page.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// BUG-014: refund butuh transaksi yang sudah ada di server. Transaksi yang belum tersinkron
/// harus ditangani dengan petunjuk jelas SEBELUM PIN diminta, bukan "transaksi tidak ditemukan".
void main() {
  testWidgets('Refund pada transaksi belum tersinkron menampilkan ajakan sinkron dan tidak meminta PIN', (tester) async {
    tester.view.physicalSize = const Size(600, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = TransaksiRepository(db.transaksiDao, db.stokDao, db.produkDao);
    const item = ItemKeranjang(produkId: 'p1', namaProduk: 'Kopi', hargaSatuan: 18000, qty: 1, lacakStok: false);
    final trx = await repo.checkout(
      tokoId: 't1',
      outletId: 'o1',
      shiftId: 's1',
      penggunaId: 'u1',
      metodeBayarId: 'm1',
      items: const [item],
      hasil: k.hitung(k.TransaksiInput(items: [
        k.ItemInput(produkId: 'p1', varianId: null, namaProduk: 'Kopi', qty: 1, hargaJual: 18000),
      ])),
      totalBayar: 18000,
    );
    expect((await db.transaksiDao.transaksiById(trx.id)).disinkronPada, isNull);

    await tester.pumpWidget(ProviderScope(
      overrides: [appDatabaseProvider.overrideWith((ref) => db)],
      child: MaterialApp(home: TransaksiDetailPage(transaksiId: trx.id)),
    ));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('transaksiDetail.refund')));
    await tester.tap(find.byKey(const Key('transaksiDetail.refund')));
    await tester.pumpAndSettle();

    expect(find.text('Transaksi belum tersinkron'), findsOneWidget);
    expect(find.byKey(const Key('transaksiDetail.sinkronDulu')), findsOneWidget);
    expect(find.textContaining('PIN'), findsNothing, reason: 'PIN belum diminta sebelum transaksi tersinkron');

    // Batal: tidak terjadi apa-apa, tidak lanjut ke refund.
    await tester.tap(find.text('Batal'));
    await tester.pumpAndSettle();
    expect(find.text('Transaksi belum tersinkron'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
