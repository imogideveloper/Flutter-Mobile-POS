import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/core/network/auth_session_store.dart';
import 'package:apps_pos/core/network/backend_api.dart';
import 'package:apps_pos/core/network/dio_backend_api.dart';
import 'package:apps_pos/features/pengeluaran/presentation/pages/settlement_page.dart';
import 'package:apps_pos/features/transaksi/data/local/tables/metode_bayar_table.dart';
import 'package:apps_pos/features/transaksi/presentation/providers/transaksi_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _Sesi extends AuthSessionStore {
  _Sesi() : super(const FlutterSecureStorage());

  @override
  Future<SesiBackend?> muat() async => const SesiBackend(
        accessToken: 't',
        refreshToken: 'r',
        tokoId: 'toko',
        outletId: 'outlet',
        penggunaId: 'u',
        perangkatId: 'p',
      );
}

class _Api implements BackendApi {
  final List<Map<String, dynamic>> kiriman = [];
  final List<String> dari = [];

  @override
  Future<dynamic> getJson({required String accessToken, required String path, Map<String, dynamic>? query}) async {
    expect(path, '/settlement/rekonsiliasi');
    dari.add(query!['dari'] as String);
    return {
      'baris': [
        {
          'tanggal': '2026-11-16',
          'metode_bayar_id': 'm1',
          'metode_nama': 'QRIS',
          'tercatat': '40000.00',
          'diterima': '39700.00',
          'biaya': '300.00',
          'selisih': '0.00',
          'status': 'cocok',
        },
        {
          'tanggal': '2026-11-17',
          'metode_bayar_id': 'm1',
          'metode_nama': 'QRIS',
          'tercatat': '60000.00',
          'diterima': '0.00',
          'biaya': '0.00',
          'selisih': '60000.00',
          'status': 'belum_dicatat',
        },
      ],
    };
  }

  @override
  Future<dynamic> postJson({required String accessToken, required String path, Map<String, dynamic>? body}) async {
    expect(path, '/settlement');
    kiriman.add(body!);
    return {};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MetodeBayarRow _metode(String id, String nama, MetodeBayarTipe tipe) => MetodeBayarRow(
      id: id,
      tokoId: 'toko',
      nama: nama,
      tipe: tipe,
      butuhGateway: false,
      masukLaci: false,
      urutan: 0,
      aktif: true,
      wajibReferensi: false,
      createdAt: 0,
      updatedAt: 0,
    );

void main() {
  test('BarisRekonsiliasi.dariJson membulatkan angka desimal server', () {
    final b = BarisRekonsiliasi.dariJson({
      'tanggal': '2026-11-16',
      'metode_bayar_id': 'm1',
      'metode_nama': 'QRIS',
      'tercatat': '40000.00',
      'diterima': '39700.00',
      'biaya': '300.00',
      'selisih': '0.00',
      'status': 'cocok',
    });
    expect(b.tercatat, 40000);
    expect(b.biaya, 300);
    expect(tanggalIso(DateTime(2026, 1, 5)), '2026-01-05');
  });

  testWidgets('menampilkan baris cocok dan belum dicatat, lalu mencatat dana masuk', (tester) async {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final api = _Api();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        backendApiProvider.overrideWithValue(api),
        authSessionStoreProvider.overrideWithValue(_Sesi()),
        metodeBayarAktifProvider.overrideWith(
          (ref) => Stream.value([
            _metode('mt', 'Tunai', MetodeBayarTipe.tunai),
            _metode('m1', 'QRIS', MetodeBayarTipe.qris),
          ]),
        ),
      ],
      child: const MaterialApp(home: SettlementPage()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Cocok'), findsOneWidget);
    expect(find.text('Belum dicatat'), findsOneWidget);
    expect(find.text('Tercatat di POS: Rp 60.000'), findsOneWidget);

    await tester.tap(find.byKey(const Key('settlement.hari.30')));
    await tester.pumpAndSettle();
    expect(DateTime.parse(api.dari.last).isBefore(DateTime.parse(api.dari.first)), isTrue, reason: 'rentang 30 hari lebih awal');

    await tester.tap(find.byKey(const Key('settlement.catat')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('settlement.jumlah')), '59700');
    await tester.enterText(find.byKey(const Key('settlement.biaya')), '300');
    await tester.tap(find.byKey(const Key('settlement.simpan')));
    await tester.pumpAndSettle();

    expect(api.kiriman.single['metode_bayar_id'], 'm1', reason: 'tunai tidak ditawarkan');
    expect(api.kiriman.single['jumlah_diterima'], '59700');
    expect(api.kiriman.single['biaya'], '300');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
