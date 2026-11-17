import 'package:apps_pos/core/network/auth_session_store.dart';
import 'package:apps_pos/core/network/backend_api.dart';
import 'package:apps_pos/core/network/dio_backend_api.dart';
import 'package:apps_pos/features/pengeluaran/presentation/pages/tutup_buku_page.dart';
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
  String? ditutupSampai;
  final List<Map<String, dynamic>> kiriman = [];
  int dibuka = 0;

  Map<String, dynamic> get _status => {
        'ditutup_sampai': ditutupSampai,
        'riwayat': [
          if (ditutupSampai != null) {'id': 'x', 'sampai': ditutupSampai, 'catatan': null, 'dibuat': '2026-11-17T00:00:00Z'},
        ],
      };

  @override
  Future<dynamic> getJson({required String accessToken, required String path, Map<String, dynamic>? query}) async {
    expect(path, '/tutup-buku');
    return _status;
  }

  @override
  Future<dynamic> postJson({required String accessToken, required String path, Map<String, dynamic>? body}) async {
    kiriman.add(body!);
    ditutupSampai = body['sampai'] as String;
    return _status;
  }

  @override
  Future<void> deleteJson({required String accessToken, required String path}) async {
    expect(path, '/tutup-buku/terakhir');
    dibuka++;
    ditutupSampai = null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('menutup buku dengan konfirmasi lalu membukanya kembali', (tester) async {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final api = _Api();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        backendApiProvider.overrideWithValue(api),
        authSessionStoreProvider.overrideWithValue(_Sesi()),
      ],
      child: const MaterialApp(home: TutupBukuPage()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Belum pernah ditutup'), findsOneWidget);
    expect(find.byKey(const Key('tutupBuku.bukaKembali')), findsNothing);

    await tester.tap(find.byKey(const Key('tutupBuku.tutup')));
    await tester.pumpAndSettle();
    expect(api.kiriman, isEmpty, reason: 'belum dikonfirmasi');
    await tester.tap(find.byKey(const Key('tutupBuku.konfirmasi')));
    await tester.pumpAndSettle();
    expect(api.kiriman.single['sampai'], matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
    expect(find.textContaining('Ditutup sampai'), findsOneWidget);

    await tester.tap(find.byKey(const Key('tutupBuku.bukaKembali')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tutupBuku.konfirmasiBuka')));
    await tester.pumpAndSettle();
    expect(api.dibuka, 1);
    expect(find.text('Belum pernah ditutup'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
