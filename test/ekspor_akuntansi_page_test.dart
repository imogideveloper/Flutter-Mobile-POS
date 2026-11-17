import 'package:apps_pos/core/network/auth_session_store.dart';
import 'package:apps_pos/core/network/backend_api.dart';
import 'package:apps_pos/core/network/dio_backend_api.dart';
import 'package:apps_pos/features/pengeluaran/presentation/pages/ekspor_akuntansi_page.dart';
import 'package:apps_pos/features/produk/presentation/providers/impor_produk_providers.dart';
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
  _Api(this.baris);

  final int baris;
  final List<Map<String, dynamic>> query = [];

  @override
  Future<dynamic> getJson({required String accessToken, required String path, Map<String, dynamic>? query}) async {
    expect(path, '/ekspor-akuntansi');
    this.query.add(query!);
    return {'nama_berkas': 'akuntansi.csv', 'jumlah_baris': baris, 'csv': 'tanggal,jenis,rincian,jumlah\n'};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<List<(String, String)>> _jalankan(WidgetTester tester, _Api api) async {
  final dibagikan = <(String, String)>[];
  await tester.pumpWidget(ProviderScope(
    overrides: [
      backendApiProvider.overrideWithValue(api),
      authSessionStoreProvider.overrideWithValue(_Sesi()),
      pembagiBerkasProvider.overrideWithValue((nama, isi) async => dibagikan.add((nama, isi))),
    ],
    child: const MaterialApp(home: EksporAkuntansiPage()),
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('ekspor.bagikan')));
  await tester.pumpAndSettle();
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 1));
  return dibagikan;
}

void main() {
  testWidgets('mengambil CSV dari server lalu membagikannya', (tester) async {
    final api = _Api(3);
    final dibagikan = await _jalankan(tester, api);
    expect(api.query.single['dari'], matches(RegExp(r'^\d{4}-\d{2}-01$')), reason: 'bawaan: awal bulan ini');
    expect(dibagikan.single.$1, 'akuntansi.csv');
    expect(dibagikan.single.$2, startsWith('tanggal,jenis,rincian,jumlah'));
  });

  testWidgets('tidak membagikan berkas bila tidak ada data', (tester) async {
    final dibagikan = await _jalankan(tester, _Api(0));
    expect(dibagikan, isEmpty);
  });
}
