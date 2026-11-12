import 'package:apps_pos/core/network/auth_session_store.dart';
import 'package:apps_pos/core/network/backend_api.dart';
import 'package:apps_pos/core/network/backend_exception.dart';
import 'package:apps_pos/core/network/dio_backend_api.dart';
import 'package:apps_pos/features/pengeluaran/domain/rekap_pajak.dart';
import 'package:apps_pos/features/pengeluaran/presentation/pages/rekap_pajak_page.dart';
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
  _Api({this.pphTerkunci = false, this.offline = false});

  final bool pphTerkunci;
  final bool offline;
  int panggilanPajak = 0;
  int panggilanPph = 0;

  @override
  Future<Map<String, dynamic>> laporanRekapPajak({
    required String accessToken,
    required String dari,
    required String sampai,
  }) async {
    if (offline) throw const BackendException(message: 'x');
    panggilanPajak++;
    return {
      'baris': [
        {'nama': 'PB1', 'tipe': 'pajak', 'persen': '10.00', 'jumlah_transaksi': 2, 'total': '4500.00'},
        {'nama': 'Service', 'tipe': 'service', 'persen': '5.00', 'jumlah_transaksi': 1, 'total': '1500.00'},
      ],
      'total_pajak': '4500.00',
      'total_service': '1500.00',
      'jumlah_transaksi': 2,
    };
  }

  @override
  Future<Map<String, dynamic>> laporanPphFinal({
    required String accessToken,
    required String dari,
    required String sampai,
  }) async {
    if (pphTerkunci) throw const BackendException(message: 'fitur_terkunci', statusCode: 403);
    panggilanPph++;
    return {
      'tarif_persen': '0.5',
      'omzet': '45000.00',
      'pph_terutang': '225.00',
      'per_bulan': [
        {'bulan': '2026-10', 'omzet': '15000.00', 'pph': '75.00'},
        {'bulan': '2026-11', 'omzet': '30000.00', 'pph': '150.00'},
      ],
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _buka(WidgetTester tester, _Api api) async {
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      backendApiProvider.overrideWithValue(api),
      authSessionStoreProvider.overrideWithValue(_Sesi()),
    ],
    child: const MaterialApp(home: RekapPajakPage()),
  ));
  await tester.pumpAndSettle();
}

Future<void> _tutup(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 1));
}

void main() {
  test('RekapPajak dan PphFinal membaca string desimal server', () {
    final r = RekapPajak.dariJson({
      'baris': [
        {'nama': 'PPN', 'tipe': 'pajak', 'persen': '11.00', 'jumlah_transaksi': 3, 'total': '1650.00'},
      ],
      'total_pajak': '1650.00',
      'total_service': '0',
      'jumlah_transaksi': 3,
    });
    expect(r.baris.single.persen, 11.0);
    expect(r.baris.single.service, isFalse);
    expect(r.totalPajak, 1650);
  });

  testWidgets('tab PPN/PB1 menampilkan total pajak, service, dan rincian', (tester) async {
    final api = _Api();
    await _buka(tester, api);
    expect(find.text('Rp 4.500'), findsWidgets);
    expect(find.byKey(const Key('rekapPajak.totalService')), findsOneWidget);
    expect(find.text('Rp 1.500'), findsWidgets);
    expect(find.text('PB1 10%'), findsOneWidget);
    expect(find.textContaining('service'), findsWidgets);
    expect(api.panggilanPph, 0, reason: 'PPh baru dimuat saat tabnya dibuka');
    await _tutup(tester);
  });

  testWidgets('tab PPh Final menampilkan estimasi, omzet, per bulan, dan catatan', (tester) async {
    final api = _Api();
    await _buka(tester, api);
    await tester.tap(find.text('PPh Final'));
    await tester.pumpAndSettle();
    expect(api.panggilanPph, 1);
    expect(find.byKey(const Key('rekapPajak.pph')), findsOneWidget);
    expect(find.text('Rp 225'), findsOneWidget);
    expect(find.text('Peredaran bruto: Rp 45.000'), findsOneWidget);
    expect(find.byKey(const Key('rekapPajak.bulan.2026-10')), findsOneWidget);
    expect(find.byKey(const Key('rekapPajak.catatan')), findsOneWidget);
    await _tutup(tester);
  });

  testWidgets('PPh Final terkunci paket: pesan jelas, tab PPN tetap berfungsi', (tester) async {
    await _buka(tester, _Api(pphTerkunci: true));
    await tester.tap(find.text('PPh Final'));
    await tester.pumpAndSettle();
    expect(find.textContaining('belum tersedia di paket'), findsOneWidget);
    await tester.tap(find.text('PPN / PB1'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('rekapPajak.totalPajak')), findsOneWidget);
    await _tutup(tester);
  });

  testWidgets('offline: pesan butuh internet', (tester) async {
    await _buka(tester, _Api(offline: true));
    expect(find.textContaining('Butuh internet'), findsOneWidget);
    await _tutup(tester);
  });
}
