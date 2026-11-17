import 'package:apps_pos/core/network/auth_session_store.dart';
import 'package:apps_pos/core/network/backend_api.dart';
import 'package:apps_pos/core/network/backend_exception.dart';
import 'package:apps_pos/core/network/dio_backend_api.dart';
import 'package:apps_pos/features/pengeluaran/domain/laba_rugi_konsolidasi.dart';
import 'package:apps_pos/features/pengeluaran/presentation/pages/laba_rugi_konsolidasi_page.dart';
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

Map<String, dynamic> _laporan({
  required String penjualan,
  required String hpp,
  required String biaya,
  required String laba,
  int transaksi = 1,
}) =>
    {
      'penjualan_kotor': penjualan,
      'diskon': '0.00',
      'penjualan_bersih': penjualan,
      'hpp': hpp,
      'laba_kotor': '0.00',
      'biaya_operasional': <Map<String, dynamic>>[],
      'total_biaya_operasional': biaya,
      'laba_bersih': laba,
      'belanja_bahan': '0.00',
      'pajak_dipungut': '0.00',
      'jumlah_transaksi': transaksi,
    };

class _Api implements BackendApi {
  _Api({this.offline = false});

  final bool offline;
  final List<Map<String, dynamic>> query = [];

  @override
  Future<dynamic> getJson({
    required String accessToken,
    required String path,
    Map<String, dynamic>? query,
  }) async {
    if (offline) throw const BackendException(message: 'x');
    expect(path, '/laporan/laba-rugi-konsolidasi');
    this.query.add(query!);
    return {
      'per_outlet': [
        {
          'outlet_id': 'oA',
          'outlet_nama': 'Outlet Pusat',
          'laporan': _laporan(penjualan: '40000.00', hpp: '16000.00', biaya: '5000.00', laba: '19000.00'),
        },
        {
          'outlet_id': 'oB',
          'outlet_nama': 'Outlet B',
          'laporan': _laporan(penjualan: '60000.00', hpp: '24000.00', biaya: '0.00', laba: '36000.00'),
        },
      ],
      'total': _laporan(penjualan: '100000.00', hpp: '40000.00', biaya: '12000.00', laba: '48000.00', transaksi: 2),
      'biaya_tanpa_outlet': '7000.00',
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _buka(WidgetTester tester, _Api api) async {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      backendApiProvider.overrideWithValue(api),
      authSessionStoreProvider.overrideWithValue(_Sesi()),
    ],
    child: const MaterialApp(home: LabaRugiKonsolidasiPage()),
  ));
  await tester.pumpAndSettle();
}

void main() {
  test('LabaRugiKonsolidasi.dariJson membaca outlet, total, dan biaya tanpa outlet', () {
    final d = LabaRugiKonsolidasi.dariJson({
      'per_outlet': [
        {
          'outlet_id': 'oA',
          'outlet_nama': 'A',
          'laporan': _laporan(penjualan: '10.00', hpp: '4.00', biaya: '1.00', laba: '5.00'),
        },
      ],
      'total': _laporan(penjualan: '10.00', hpp: '4.00', biaya: '3.00', laba: '3.00'),
      'biaya_tanpa_outlet': '2.00',
    });
    expect(d.perOutlet.single.outletNama, 'A');
    expect(d.perOutlet.single.laporan.labaBersih, 5);
    expect(d.total.totalBiayaOperasional, 3);
    expect(d.biayaTanpaOutlet, 2);
  });

  testWidgets('menampilkan total toko, tiap outlet, dan biaya tanpa outlet', (tester) async {
    final api = _Api();
    await _buka(tester, api);

    expect(find.byKey(const Key('konsolidasi.totalLaba')), findsOneWidget);
    expect(find.text('Rp 48.000'), findsWidgets, reason: 'laba bersih total');
    expect(find.byKey(const Key('konsolidasi.outlet.oA')), findsOneWidget);
    expect(find.byKey(const Key('konsolidasi.outlet.oB')), findsOneWidget);
    expect(find.text('Outlet Pusat'), findsOneWidget);
    expect(find.text('2 outlet · 2 transaksi'), findsOneWidget);
    expect(find.byKey(const Key('konsolidasi.biayaTanpaOutlet')), findsOneWidget);
    expect(find.text('-Rp 7.000'), findsOneWidget);
    expect(api.query.single['dari'], contains('-01T00:00:00'), reason: 'rentang default bulan ini');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('offline: pesan butuh internet', (tester) async {
    await _buka(tester, _Api(offline: true));
    expect(find.byKey(const Key('konsolidasi.error')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
