import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/core/network/auth_session_store.dart';
import 'package:apps_pos/core/network/backend_api.dart';
import 'package:apps_pos/core/network/connectivity_provider.dart';
import 'package:apps_pos/core/network/dio_backend_api.dart';
import 'package:apps_pos/core/providers/database_provider.dart';
import 'package:apps_pos/features/promo/domain/pajak.dart';
import 'package:apps_pos/features/promo/presentation/pages/pajak_form_page.dart';
import 'package:apps_pos/features/promo/data/local/tables/pajak_table.dart' show PajakTipe;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// PajakFormPage memanggil context.pop() dari go_router. Tanpa GoRouter
/// sungguhan ini SEBENARNYA throw "No GoRouter found in context" -
/// sebelumnya tidak ketahuan di sini krn _simpan() punya try/catch yang
/// diam-diam menelan error itu (test tetap "lulus" tapi tidak benar2
/// menguji bahwa pop sukses). Rute nested '/' -> 'form' (bukan cuma '/')
/// supaya pop() ADA tujuan - GoRouter throw "There is nothing to pop"
/// kalau stacknya cuma 1 level, beda dari Navigator.pop() biasa.
Widget _bungkusRouter(Widget child) => MaterialApp.router(
      routerConfig: GoRouter(
        initialLocation: '/form',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const Scaffold(body: SizedBox()),
            routes: [GoRoute(path: 'form', builder: (context, state) => child)],
          ),
        ],
      ),
    );

class _FakeAuthSessionStoreTerisi extends AuthSessionStore {
  _FakeAuthSessionStoreTerisi() : super(const FlutterSecureStorage());

  @override
  Future<SesiBackend?> muat() async => const SesiBackend(
        accessToken: 'token',
        refreshToken: 'refresh',
        tokoId: 'toko-1',
        outletId: 'outlet-1',
        penggunaId: 'pengguna-1',
        perangkatId: 'perangkat-1',
      );
}

class _FakeBackendApiPajak implements BackendApi {
  Map<String, dynamic>? bodyDiterima;
  String? pathDiterima;

  @override
  Future<dynamic> postJson({
    required String accessToken,
    required String path,
    Map<String, dynamic>? body,
  }) async {
    pathDiterima = path;
    bodyDiterima = body;
    return {
      'id': 'pajak-baru',
      'nama': body!['nama'],
      'tipe': body['tipe'],
      'persen': body['persen'],
      'termasuk_harga': body['termasuk_harga'],
      'urutan': body['urutan'],
      'aktif': true,
    };
  }

  @override
  Future<dynamic> patchJson({
    required String accessToken,
    required String path,
    required Map<String, dynamic> body,
  }) async {
    pathDiterima = path;
    bodyDiterima = body;
    return {
      'id': 'pajak-1',
      'nama': body['nama'],
      'tipe': body['tipe'],
      'persen': body['persen'],
      'termasuk_harga': body['termasuk_harga'],
      'urutan': body['urutan'],
      'aktif': body['aktif'],
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  testWidgets('tambah pajak baru - isi form lalu simpan terkirim ke backend', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final fakeBackend = _FakeBackendApiPajak();

    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWith((ref) => db),
        authSessionStoreProvider.overrideWithValue(_FakeAuthSessionStoreTerisi()),
        backendApiProvider.overrideWithValue(fakeBackend),
        isOnlineProvider.overrideWith((ref) => Stream.value(true)),
      ],
      child: _bungkusRouter(const PajakFormPage()),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('pajakForm.nama')), 'PPN');
    await tester.enterText(find.byKey(const Key('pajakForm.persen')), '11');
    await tester.tap(find.byKey(const Key('pajakForm.simpan')));
    await tester.pumpAndSettle();

    expect(fakeBackend.pathDiterima, '/pajak');
    expect(fakeBackend.bodyDiterima!['nama'], 'PPN');
    expect(fakeBackend.bodyDiterima!['persen'], '11');

    // currentTokoIdProvider tidak di-override (NotifierProvider privat,
    // tidak bisa disubclass dari luar) - defaultnya 'toko-default', bukan
    // 'toko-1' (sesi backend fake). Konsisten dgn perilaku app sungguhan
    // sebelum pairing.
    //
    // PENTING: pakai query SEKALI JALAN (.get()), BUKAN .watch().first -
    // ditemukan lewat timeout 10 menit kalau dipakai: stream drift di
    // dalam testWidgets tidak pernah mengirim nilai pertamanya tanpa
    // tester.pump() lanjutan, jadi .first menggantung selamanya.
    final rows = await db.select(db.pajak).get();
    expect(rows.single.nama, 'PPN');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('validasi - persen kosong menampilkan error, tidak memanggil backend', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final fakeBackend = _FakeBackendApiPajak();

    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWith((ref) => db),
        authSessionStoreProvider.overrideWithValue(_FakeAuthSessionStoreTerisi()),
        backendApiProvider.overrideWithValue(fakeBackend),
        isOnlineProvider.overrideWith((ref) => Stream.value(true)),
      ],
      child: _bungkusRouter(const PajakFormPage()),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('pajakForm.nama')), 'PPN');
    await tester.tap(find.byKey(const Key('pajakForm.simpan')));
    await tester.pumpAndSettle();

    expect(find.text('Persen wajib diisi'), findsOneWidget);
    expect(fakeBackend.pathDiterima, isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('kondisi offline - banner tampil & tombol simpan nonaktif', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final fakeBackend = _FakeBackendApiPajak();

    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWith((ref) => db),
        authSessionStoreProvider.overrideWithValue(_FakeAuthSessionStoreTerisi()),
        backendApiProvider.overrideWithValue(fakeBackend),
        isOnlineProvider.overrideWith((ref) => Stream.value(false)),
      ],
      child: _bungkusRouter(const PajakFormPage()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Butuh internet untuk mengubah pengaturan'), findsOneWidget);
    final tombol = tester.widget<FilledButton>(find.descendant(
      of: find.byKey(const Key('pajakForm.simpan')),
      matching: find.byType(FilledButton),
    ));
    expect(tombol.onPressed, isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('mode edit - form terisi data existing & kirim PATCH', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final fakeBackend = _FakeBackendApiPajak();
    const pajakLama = Pajak(
      id: 'pajak-1',
      tokoId: 'toko-1',
      nama: 'PPN',
      tipe: PajakTipe.pajak,
      persen: 11,
      termasukHarga: false,
      urutan: 0,
      aktif: true,
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWith((ref) => db),
        authSessionStoreProvider.overrideWithValue(_FakeAuthSessionStoreTerisi()),
        backendApiProvider.overrideWithValue(fakeBackend),
        isOnlineProvider.overrideWith((ref) => Stream.value(true)),
      ],
      child: _bungkusRouter(PajakFormPage(pajakEdit: pajakLama)),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Ubah Pajak/Service'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('pajakForm.nama')), 'PPN 12%');
    await tester.tap(find.byKey(const Key('pajakForm.simpan')));
    await tester.pumpAndSettle();

    expect(fakeBackend.pathDiterima, '/pajak/pajak-1');
    expect(fakeBackend.bodyDiterima!['nama'], 'PPN 12%');
    expect(fakeBackend.bodyDiterima!['aktif'], true);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
