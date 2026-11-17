import 'package:apps_pos/core/network/auth_session_store.dart';
import 'package:apps_pos/core/network/backend_api.dart';
import 'package:apps_pos/core/network/dio_backend_api.dart';
import 'package:apps_pos/features/pengeluaran/presentation/pages/aset_tetap_page.dart';
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
  final List<Map<String, dynamic>> perubahan = [];

  @override
  Future<dynamic> getJson({required String accessToken, required String path, Map<String, dynamic>? query}) async {
    expect(path, '/aset-tetap');
    return {
      'per': '2026-03-31',
      'aset': [
        {
          'id': 'a1',
          'nama': 'Mesin kopi',
          'harga_perolehan': '24000000.00',
          'tanggal_perolehan': '2026-01-10',
          'nilai_residu': '0.00',
          'umur_bulan': 24,
          'bulan_berjalan': 3,
          'akumulasi_penyusutan': '3000000.00',
          'nilai_buku': '21000000.00',
          'penyusutan_bulan_ini': '1000000.00',
        },
      ],
      'total_nilai_buku': '21000000.00',
      'total_penyusutan_bulan_ini': '1000000.00',
    };
  }

  @override
  Future<dynamic> postJson({required String accessToken, required String path, Map<String, dynamic>? body}) async {
    kiriman.add(body!);
    return {};
  }

  @override
  Future<dynamic> patchJson({required String accessToken, required String path, required Map<String, dynamic> body}) async {
    expect(path, '/aset-tetap/a1');
    perubahan.add(body);
    return {};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('menampilkan aset dan total, menolak input tidak sah, lalu menambah aset', (tester) async {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final api = _Api();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        backendApiProvider.overrideWithValue(api),
        authSessionStoreProvider.overrideWithValue(_Sesi()),
      ],
      child: const MaterialApp(home: AsetTetapPage()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Mesin kopi'), findsOneWidget);
    expect(find.text('Rp 21.000.000'), findsWidgets);
    expect(find.text('Berjalan 3 bulan - akumulasi Rp 3.000.000'), findsOneWidget);

    await tester.tap(find.byKey(const Key('aset.tambah')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('aset.simpan')));
    await tester.pump();
    expect(find.byKey(const Key('aset.salah')), findsOneWidget);
    expect(api.kiriman, isEmpty);

    await tester.enterText(find.byKey(const Key('aset.nama')), 'Kulkas');
    await tester.enterText(find.byKey(const Key('aset.harga')), '6000000');
    await tester.enterText(find.byKey(const Key('aset.residu')), '600000');
    await tester.tap(find.byKey(const Key('aset.simpan')));
    await tester.pumpAndSettle();

    expect(api.kiriman.single['nama'], 'Kulkas');
    expect(api.kiriman.single['harga_perolehan'], '6000000');
    expect(api.kiriman.single['nilai_residu'], '600000');
    expect(api.kiriman.single['umur_bulan'], 48);

    await tester.tap(find.byKey(const Key('aset.ubah.a1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('aset.umur')), '36');
    await tester.tap(find.byKey(const Key('aset.simpan')));
    await tester.pumpAndSettle();
    expect(api.perubahan.single['umur_bulan'], 36);
    expect(api.perubahan.single['harga_perolehan'], '24000000', reason: 'nilai awal terisi dari aset');
    expect(api.perubahan.single['tanggal_perolehan'], '2026-01-10');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
