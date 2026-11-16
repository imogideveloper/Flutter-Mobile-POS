import 'dart:convert';
import 'dart:typed_data';

import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/features/produk/data/local/tables/produk_table.dart' hide Produk;
import 'package:apps_pos/features/stok/data/local/tables/mutasi_stok_table.dart' show MutasiJenis;
import 'package:apps_pos/features/transaksi/presentation/providers/qris_providers.dart';
import 'package:apps_pos/main.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'test_helpers.dart';

// PNG 1x1 valid.
final _png = Uint8List.fromList(base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=='));

Future<AppDatabase> _siapkan() async {
  final db = AppDatabase(NativeDatabase.memory());
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
  return db;
}

Future<void> _keLayarQris(WidgetTester tester, AppDatabase db, Uint8List? gambar) async {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      ...overridesSudahLogin(db),
      qrisTokoProvider.overrideWith((ref) async => gambar),
    ],
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
  await tester.tap(find.text('Bayar Rp15.000'));
  await tester.pumpAndSettle();
  // Halaman QRIS punya Timer.periodic: jangan pumpAndSettle setelah masuk.
  await tester.tap(find.text('QRIS\n(cek manual)'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('layar bayar QRIS menampilkan gambar QRIS usaha, bukan QR tiruan', (tester) async {
    final db = await _siapkan();
    addTearDown(db.close);
    await _keLayarQris(tester, db, _png);

    expect(find.byKey(const Key('bayarQrisPage.gambarQris')), findsOneWidget);
    expect(find.byKey(const Key('bayarQrisPage.belumAdaQris')), findsNothing);
    expect(find.byType(QrImageView), findsNothing, reason: 'QR tiruan POS-MOCK tidak boleh muncul lagi');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('tanpa gambar QRIS: pesan petunjuk, tanpa QR tiruan, konfirmasi manual tetap tersedia', (tester) async {
    final db = await _siapkan();
    addTearDown(db.close);
    await _keLayarQris(tester, db, null);

    expect(find.byKey(const Key('bayarQrisPage.belumAdaQris')), findsOneWidget);
    expect(find.byKey(const Key('bayarQrisPage.gambarQris')), findsNothing);
    expect(find.byType(QrImageView), findsNothing);
    expect(find.byKey(const Key('bayarQrisPage.konfirmasiCekDana')), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
