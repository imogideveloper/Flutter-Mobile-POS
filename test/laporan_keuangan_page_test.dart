import 'package:apps_pos/core/network/auth_session_store.dart';
import 'package:apps_pos/core/network/backend_api.dart';
import 'package:apps_pos/core/network/dio_backend_api.dart';
import 'package:apps_pos/features/pengeluaran/presentation/pages/laporan_keuangan_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

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
  final List<Map<String, dynamic>?> query = [];

  @override
  Future<dynamic> getJson({required String accessToken, required String path, Map<String, dynamic>? query}) async {
    expect(path, '/laporan-keuangan');
    this.query.add(query);
    Map<String, dynamic> b(String kode, String nama, String j) => {'kode_akun': kode, 'nama': nama, 'jumlah': j};
    return {
      'laba_rugi': {
        'pendapatan': [b('4-1000', 'Penjualan makanan & minuman', '40000.00')],
        'total_pendapatan': '40000.00',
        'hpp': [b('5-1000', 'HPP bahan baku', '16000.00')],
        'total_hpp': '16000.00',
        'laba_kotor': '24000.00',
        'beban': [b('6-1100', 'Beban sewa', '5000.00')],
        'total_beban': '5000.00',
        'laba_bersih': '19000.00',
      },
      'arus_kas': {
        'masuk': [{'keterangan': 'Penjualan - Tunai', 'jumlah': '40000.00'}],
        'total_masuk': '40000.00',
        'keluar': [{'keterangan': 'Beban sewa', 'kode_akun': '6-1100', 'jumlah': '5000.00'}, {'keterangan': 'HPP bahan baku', 'kode_akun': '5-1000', 'jumlah': '7000.00'}],
        'total_keluar': '5000.00',
        'kenaikan_kas': '35000.00',
      },
      'posisi': {
        'per_tanggal': '2026-11-25',
        'aset': [b('1-1100', 'Kas', '35000.00')],
        'total_aset': '35000.00',
        'kewajiban': <Map<String, dynamic>>[],
        'total_kewajiban': '0.00',
        'ekuitas': '35000.00',
      },
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));

  testWidgets('Laporan keuangan menampilkan laba rugi per akun, arus kas, dan neraca; bulan bisa dimundurkan', (tester) async {
    tester.view.physicalSize = const Size(900, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final api = _Api();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        backendApiProvider.overrideWithValue(api),
        authSessionStoreProvider.overrideWithValue(_Sesi()),
      ],
      child: const MaterialApp(home: LaporanKeuanganPage()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Laporan Laba Rugi'), findsOneWidget);
    expect(find.text('Laporan Posisi Keuangan (Neraca)'), findsOneWidget);
    expect(find.text('Laporan Arus Kas'), findsOneWidget);
    expect(find.text('Usaha untung'), findsOneWidget, reason: 'ringkasan dalam kalimat biasa');
    expect(find.text('Penjualan'), findsOneWidget, reason: 'nama akun bahasa sehari-hari, tanpa kode');
    expect(find.textContaining('4-1000'), findsNothing);
    expect(find.text('Sewa tempat'), findsNWidgets(2), reason: 'di laba rugi dan arus kas');
    expect(find.text('Belanja bahan baku'), findsOneWidget, reason: 'di arus kas, bukan bahan yang terjual');
    expect(find.text('Laba bersih'), findsOneWidget);
    expect(find.text('Total kewajiban + modal'), findsOneWidget);
    expect(find.text('Modal pemilik & laba usaha'), findsOneWidget);
    final awal = api.query.single!['dari'] as String;
    expect(awal.endsWith('-01'), isTrue, reason: 'periode mulai tanggal 1 bulan berjalan');

    await tester.tap(find.byKey(const Key('laporanKeuangan.bulanSebelumnya')));
    await tester.pumpAndSettle();
    expect(api.query, hasLength(2));
    expect(api.query.last!['dari'], isNot(awal));
  });
}
