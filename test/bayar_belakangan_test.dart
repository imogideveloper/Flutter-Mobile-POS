import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/features/pelanggan/presentation/providers/piutang_providers.dart';
import 'package:apps_pos/features/produk/data/local/tables/produk_table.dart';
import 'package:apps_pos/features/stok/data/local/tables/mutasi_stok_table.dart';
import 'package:apps_pos/features/transaksi/data/local/tables/transaksi_table.dart';
import 'package:apps_pos/features/transaksi/presentation/pages/order_belum_dibayar_page.dart';
import 'package:apps_pos/main.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'test_helpers.dart';

TransaksiRow _row({
  String id = 't',
  bool bayarBelakangan = true,
  TransaksiStatus status = TransaksiStatus.selesai,
  StatusBayarTransaksi statusBayar = StatusBayarTransaksi.belumBayar,
}) =>
    TransaksiRow(
      id: id,
      tokoId: 'toko-default',
      outletId: 'outlet-default',
      penggunaId: 'p',
      nomorStruk: 'S',
      tanggal: 1,
      status: status,
      subtotal: 1000,
      totalDiskon: 0,
      totalPajak: 0,
      pembulatan: 0,
      total: 1000,
      totalBayar: 0,
      kembalian: 0,
      statusBayar: statusBayar,
      sisaTagihan: 1000,
      poinDitukar: 0,
      diskonPoin: 0,
      bayarBelakangan: bayarBelakangan,
      createdAt: 1,
      updatedAt: 1,
    );

void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));

  test('filterOrderBelumDibayar: hanya order bayar belakangan yang selesai dan belum lunas', () {
    final hasil = filterOrderBelumDibayar([
      _row(id: 'ya-belum'),
      _row(id: 'ya-sebagian', statusBayar: StatusBayarTransaksi.sebagian),
      _row(id: 'lunas', statusBayar: StatusBayarTransaksi.lunas),
      _row(id: 'kasbon-biasa', bayarBelakangan: false),
      _row(id: 'draft', status: TransaksiStatus.draft),
    ]);
    expect(hasil.map((t) => t.id), ['ya-belum', 'ya-sebagian']);
  });

  testWidgets('Terima Order: tercatat belum dibayar tanpa pelanggan, lalu dilunasi dari Order belum dibayar', (tester) async {
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
    await db.fiturDao.simpanStatusFitur(
      tokoId: 'toko-default',
      paket: 'Gratis',
      kodeFiturAktif: const ['pay_later'],
      batasPerKode: const {},
      updatedAt: 0,
    );

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

    await tester.tap(find.byKey(const Key('keranjangForm.terimaOrder')));
    await tester.pumpAndSettle();

    // Struk menyebut order diterima, bukan "kasbon".
    expect(find.text('Order diterima, bayar nanti'), findsOneWidget);
    expect(find.textContaining('kasbon'), findsNothing);

    final t = (await db.select(db.transaksi).get()).single;
    expect(t.bayarBelakangan, isTrue);
    expect(t.statusBayar, StatusBayarTransaksi.belumBayar);
    expect(t.total, 50000);
    expect(t.sisaTagihan, 50000);
    expect(t.totalBayar, 0);
    expect(t.pelangganId, isNull, reason: 'tanpa pelanggan, bukan kasbon');
    expect(t.jatuhTempo, isNull);
    expect(await db.select(db.pembayaran).get(), isEmpty, reason: 'belum ada uang masuk');

    // Bukan piutang kasbon.
    final container = ProviderScope.containerOf(tester.element(find.byType(AppsPosApp)));
    expect(container.read(piutangPelangganProvider).value ?? [], isEmpty);

    // Pelunasan lewat layar Order belum dibayar (menu Lainnya).
    await tester.tap(find.text('Lainnya'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Order belum dibayar'));
    await tester.pumpAndSettle();
    expect(find.byKey(Key('orderBelumDibayar.kartu.${t.id}')), findsOneWidget);

    await tester.tap(find.byKey(Key('orderBelumDibayar.bayar.${t.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('orderBelumDibayar.metode.metode-tunai-uji')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('orderBelumDibayar.jumlah')), '20000');
    await tester.tap(find.byKey(const Key('orderBelumDibayar.catat')));
    await tester.pumpAndSettle();

    // Sebagian dulu: masih di daftar dengan sisa 30.000.
    var sesudah = (await db.select(db.transaksi).get()).single;
    expect(sesudah.statusBayar, StatusBayarTransaksi.sebagian);
    expect(sesudah.sisaTagihan, 30000);
    expect(find.text('Dibayar sebagian'), findsOneWidget);

    await tester.tap(find.byKey(Key('orderBelumDibayar.bayar.${t.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('orderBelumDibayar.metode.metode-kartu-uji')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('orderBelumDibayar.catat'))); // jumlah bawaan = sisa
    await tester.pumpAndSettle();

    sesudah = (await db.select(db.transaksi).get()).single;
    expect(sesudah.statusBayar, StatusBayarTransaksi.lunas);
    expect(sesudah.sisaTagihan, 0);
    final bayar = await db.select(db.pembayaran).get();
    expect(bayar.map((p) => p.jumlah).toList()..sort(), [20000, 30000]);
    expect(find.text('Tidak ada order yang menunggu pembayaran.'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
