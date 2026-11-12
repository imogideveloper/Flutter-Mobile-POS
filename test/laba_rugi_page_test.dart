import 'package:apps_pos/core/network/auth_session_store.dart';
import 'package:apps_pos/core/network/backend_api.dart';
import 'package:apps_pos/core/network/backend_exception.dart';
import 'package:apps_pos/core/network/dio_backend_api.dart';
import 'package:apps_pos/features/pengeluaran/domain/laba_rugi.dart';
import 'package:apps_pos/features/pengeluaran/presentation/pages/laba_rugi_page.dart';
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
  _Api({this.offline = false, this.labaBersih = '10000.00'});

  final bool offline;
  final String labaBersih;
  final List<List<String>> permintaan = [];

  @override
  Future<Map<String, dynamic>> laporanLabaRugi({
    required String accessToken,
    required String dari,
    required String sampai,
  }) async {
    if (offline) throw const BackendException(message: 'x');
    permintaan.add([dari, sampai]);
    return {
      'penjualan_kotor': '30000.00',
      'diskon': '0.00',
      'penjualan_bersih': '30000.00',
      'hpp': '12000.00',
      'laba_kotor': '18000.00',
      'biaya_operasional': [
        {'kategori': 'gas_lpg', 'total': '5000.00'},
        {'kategori': 'sewa', 'total': '3000.00'},
      ],
      'total_biaya_operasional': '8000.00',
      'laba_bersih': labaBersih,
      'belanja_bahan': '10000.00',
      'pajak_dipungut': '3300.00',
      'jumlah_transaksi': 1,
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
    child: const MaterialApp(home: LabaRugiPage()),
  ));
  await tester.pumpAndSettle();
}

Future<void> _tutup(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 1));
}

void main() {
  test('isoDenganOffset memuat offset zona waktu dan format tetap', () {
    final s = isoDenganOffset(DateTime(2026, 11, 2, 0, 5, 9));
    expect(s, matches(RegExp(r'^2026-11-02T00:05:09[+-]\d{2}:\d{2}$')));
  });

  test('LabaRugi.dariJson membaca string desimal dari server', () {
    final d = LabaRugi.dariJson({
      'penjualan_kotor': '30000.00',
      'diskon': '0',
      'penjualan_bersih': '30000.00',
      'hpp': '12000.000000',
      'laba_kotor': '18000',
      'biaya_operasional': [
        {'kategori': 'sewa', 'total': '3000.00'},
      ],
      'total_biaya_operasional': '3000.00',
      'laba_bersih': '-1500.00',
      'belanja_bahan': '0',
      'pajak_dipungut': '0',
      'jumlah_transaksi': 2,
    });
    expect(d.hpp, 12000);
    expect(d.biayaOperasional, {'sewa': 3000});
    expect(d.labaBersih, -1500);
    expect(d.rugi, isTrue);
  });

  testWidgets('menampilkan rincian laba rugi dan catatan', (tester) async {
    final api = _Api();
    await _buka(tester, api);
    expect(find.byKey(const Key('labaRugi.labaBersih')), findsOneWidget);
    expect(find.text('Rp 10.000'), findsWidgets);
    expect(find.byKey(const Key('labaRugi.hpp')), findsOneWidget);
    expect(find.text('-Rp 12.000'), findsOneWidget);
    expect(find.text('Rp 18.000'), findsOneWidget);
    expect(find.byKey(const Key('labaRugi.biaya.gas_lpg')), findsOneWidget);
    expect(find.byKey(const Key('labaRugi.catatan')), findsOneWidget);
    // rentang default: bulan ini; sampai = awal hari berikutnya (eksklusif)
    expect(api.permintaan.single[0], contains('-01T00:00:00'));
    await _tutup(tester);
  });

  testWidgets('rugi ditandai dan memakai label Rugi bersih', (tester) async {
    await _buka(tester, _Api(labaBersih: '-2500.00'));
    expect(find.text('Rugi bersih'), findsWidgets);
    expect(find.text('-Rp 2.500'), findsWidgets);
    await _tutup(tester);
  });

  testWidgets('offline: pesan butuh internet', (tester) async {
    await _buka(tester, _Api(offline: true));
    expect(find.byKey(const Key('labaRugi.error')), findsOneWidget);
    await _tutup(tester);
  });
}
