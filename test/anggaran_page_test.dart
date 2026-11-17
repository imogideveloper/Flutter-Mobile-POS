import 'package:apps_pos/core/network/auth_session_store.dart';
import 'package:apps_pos/core/network/backend_api.dart';
import 'package:apps_pos/core/network/dio_backend_api.dart';
import 'package:apps_pos/features/pengeluaran/presentation/pages/anggaran_page.dart';
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
  final List<String> bulanDiminta = [];
  final List<Map<String, dynamic>> kiriman = [];
  final List<Map<String, dynamic>> salinan = [];

  @override
  Future<dynamic> getJson({required String accessToken, required String path, Map<String, dynamic>? query}) async {
    expect(path, '/anggaran');
    bulanDiminta.add(query!['bulan'] as String);
    return {
      'bulan': query['bulan'],
      'hari_berjalan': 10,
      'jumlah_hari': 30,
      'baris': [
        {
          'kategori': 'gas_lpg',
          'anggaran': '100000.00',
          'realisasi': '90000.00',
          'sisa': '10000.00',
          'persen': '0.9000',
          'proyeksi': '270000.00',
          'status': 'waspada',
        },
        {
          'kategori': 'kemasan',
          'anggaran': '0.00',
          'realisasi': '50000.00',
          'sisa': '-50000.00',
          'persen': null,
          'proyeksi': '150000.00',
          'status': 'tanpa_anggaran',
        },
      ],
      'total_anggaran': '100000.00',
      'total_realisasi': '140000.00',
      'total_proyeksi': '420000.00',
      'penjualan_realisasi': '200000.00',
      'penjualan_proyeksi': '600000.00',
      'arus_kas_proyeksi': '180000.00',
    };
  }

  @override
  Future<dynamic> postJson({required String accessToken, required String path, Map<String, dynamic>? body}) async {
    expect(path, '/anggaran/salin');
    salinan.add(body!);
    return {'disalin': 2};
  }

  @override
  Future<dynamic> putJsonBody({required String accessToken, required String path, required Map<String, dynamic> body}) async {
    expect(path, '/anggaran');
    kiriman.add(body);
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('BarisAnggaran: rasio dipotong di 1 dan nol bila tanpa anggaran', () {
    BarisAnggaran b(int a, int r) =>
        BarisAnggaran(kategori: 'sewa', anggaran: a, realisasi: r, proyeksi: r, status: 'aman');
    expect(b(100, 50).rasio, 0.5);
    expect(b(100, 250).rasio, 1.0);
    expect(b(0, 50).rasio, 0.0);
    expect(bulanIso(DateTime(2026, 3, 9)), '2026-03');
  });

  testWidgets('menampilkan proyeksi dan status, mengatur anggaran, dan pindah bulan', (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final api = _Api();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        backendApiProvider.overrideWithValue(api),
        authSessionStoreProvider.overrideWithValue(_Sesi()),
      ],
      child: const MaterialApp(home: AnggaranPage()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Hampir habis'), findsOneWidget);
    expect(find.text('Belum dianggarkan'), findsOneWidget);
    expect(find.text('Selisih kasar Rp 180.000'), findsOneWidget);
    expect(find.text('Anggaran Rp 100.000 - terpakai Rp 90.000'), findsOneWidget);

    await tester.tap(find.byKey(const Key('anggaran.atur')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('anggaran.jumlah')), '750000');
    await tester.tap(find.byKey(const Key('anggaran.simpan')));
    await tester.pumpAndSettle();
    expect(api.kiriman.single['kategori'], 'belanja_bahan');
    expect(api.kiriman.single['jumlah'], '750000');
    expect(api.kiriman.single['bulan'], api.bulanDiminta.first);

    await tester.tap(find.byKey(const Key('anggaran.salin')));
    await tester.pumpAndSettle();
    expect(api.salinan.single['ke'], api.bulanDiminta.first);
    expect(api.salinan.single['dari'], isNot(api.salinan.single['ke']));

    await tester.tap(find.byKey(const Key('anggaran.sebelumnya')));
    await tester.pumpAndSettle();
    expect(api.bulanDiminta.last, isNot(api.bulanDiminta.first));

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
