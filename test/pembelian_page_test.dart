import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/core/network/auth_session_store.dart';
import 'package:apps_pos/core/network/backend_api.dart';
import 'package:apps_pos/core/network/dio_backend_api.dart';
import 'package:apps_pos/core/providers/session_provider.dart';
import 'package:apps_pos/features/produk/data/local/tables/produk_table.dart' hide Produk;
import 'package:apps_pos/features/stok/presentation/pages/pembelian_page.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'test_helpers.dart';

class _Sesi extends AuthSessionStore {
  _Sesi() : super(const FlutterSecureStorage());

  @override
  Future<SesiBackend?> muat() async => const SesiBackend(
        accessToken: 't',
        refreshToken: 'r',
        tokoId: tokoIdPlaceholder,
        outletId: outletIdPlaceholder,
        penggunaId: 'u',
        perangkatId: 'p',
      );
}

/// Server tiruan: menyimpan pembelian di memori dan meniru terima/lunas.
class _Api implements BackendApi {
  final pembelian = <Map<String, dynamic>>[];
  final pemasok = <Map<String, dynamic>>[];
  final jalur = <String>[];

  @override
  Future<dynamic> getJson({required String accessToken, required String path, Map<String, dynamic>? query}) async {
    if (path == '/pembelian') return pembelian;
    if (path == '/supplier') return pemasok;
    fail('jalur tak terduga $path');
  }

  @override
  Future<dynamic> postJson({required String accessToken, required String path, Map<String, dynamic>? body}) async {
    jalur.add(path);
    if (path == '/supplier') {
      final s = {'id': 's1', 'nama': body!['nama']};
      pemasok.add(s);
      return s;
    }
    if (path == '/pembelian') {
      final items = body!['items'] as List;
      final total = items.fold<double>(0, (a, i) => a + double.parse(i['qty'] as String) * double.parse(i['harga_satuan'] as String));
      final p = {
        'id': 'pb1',
        'nomor': body['nomor'],
        'tanggal': body['tanggal'],
        'status': 'draft',
        'status_bayar': 'belum',
        'total': '$total',
        'supplier_id': body['supplier_id'],
        'items': [
          for (final i in items) {'nama_produk': 'Biji Kopi', 'qty': i['qty'], 'harga_satuan': i['harga_satuan']},
        ],
      };
      pembelian.add(p);
      return p;
    }
    if (path.endsWith('/terima')) pembelian.single['status'] = 'diterima';
    if (path.endsWith('/lunas')) pembelian.single['status_bayar'] = 'lunas';
    return pembelian.single;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));

  test('utang pemasok = pembelian sudah diterima tetapi belum lunas', () {
    PembelianRingkas p(String status, String bayar, int total) => PembelianRingkas(
          id: '$status$bayar',
          nomor: 'x',
          tanggal: DateTime(2026, 11, 26),
          status: status,
          statusBayar: bayar,
          total: total,
          pemasokId: null,
          items: const [],
        );
    expect(totalUtangPemasok([p('diterima', 'belum', 100), p('diterima', 'lunas', 50), p('draft', 'belum', 30)]), 100);
  });

  testWidgets('catat pembelian dari pemasok baru, barang diterima, bayar belakangan: muncul sebagai utang', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.produkDao.upsertProduk(ProdukCompanion.insert(
      id: 'p1',
      tokoId: tokoIdPlaceholder,
      nama: 'Biji Kopi',
      tipe: ProdukTipe.barang,
      hpp: const Value(120000),
      hargaJual: const Value(0),
      createdAt: 0,
      updatedAt: 0,
    ));
    final api = _Api();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        ...overridesSudahLogin(db).where((o) => o.toString().contains('AuthSessionStore') == false),
        authSessionStoreProvider.overrideWithValue(_Sesi()),
        backendApiProvider.overrideWithValue(api),
      ],
      child: const MaterialApp(home: PembelianPage()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Semua pembelian sudah lunas'), findsOneWidget);

    await tester.tap(find.byKey(const Key('pembelian.tambah')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pembelian.tambahPemasok')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('pembelian.namaPemasok')), 'Toko Biji');
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('pembelian.tambahBarang')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('pembelian.qty')), '2');
    await tester.tap(find.byKey(const Key('pembelian.simpanBarang')));
    await tester.pumpAndSettle();
    expect(find.text('Total Rp240.000'), findsOneWidget, reason: 'harga beli bawaan dari HPP produk');

    await tester.tap(find.byKey(const Key('pembelian.dibayar')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('pembelian.simpan')));
    await tester.tap(find.byKey(const Key('pembelian.simpan')));
    await tester.pumpAndSettle();

    expect(api.jalur, ['/supplier', '/pembelian', '/pembelian/pb1/terima'], reason: 'tidak ditandai lunas');
    expect(api.pembelian.single['supplier_id'], 's1');
    expect(find.text('Rp240.000'), findsWidgets, reason: 'utang ke pemasok tampil');
    expect(find.text('1 pembelian belum dibayar'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
