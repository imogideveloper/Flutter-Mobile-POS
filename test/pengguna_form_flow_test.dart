import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/core/network/auth_session_store.dart';
import 'package:apps_pos/core/network/backend_api.dart';
import 'package:apps_pos/core/network/connectivity_provider.dart';
import 'package:apps_pos/core/network/dio_backend_api.dart';
import 'package:apps_pos/core/providers/database_provider.dart';
import 'package:apps_pos/features/auth/presentation/pages/pengguna_form_page.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Tahap 5b (desain #1) - PenggunaFormPage ditulis ulang jadi ONLINE
/// (server CRUD, bukan lokal lagi spt versi Tahap 5) - lihat
/// _bungkusRouter yang sama dgn pajak_form_flow_test.dart (context.pop()
/// dari go_router butuh GoRouter sungguhan di widget tree).
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

class _FakeBackendApiPengguna implements BackendApi {
  Map<String, dynamic>? bodyDiterima;
  String? pathDiterima;

  @override
  Future<dynamic> getJson({
    required String accessToken,
    required String path,
    Map<String, dynamic>? query,
  }) async {
    if (path == '/roles') {
      return [
        {'id': 'role-kasir', 'nama': 'Kasir', 'is_system': true},
      ];
    }
    if (path == '/outlets') {
      return [
        {'id': 'outlet-1', 'nama': 'Outlet Pusat'},
      ];
    }
    return <dynamic>[];
  }

  @override
  Future<dynamic> postJson({
    required String accessToken,
    required String path,
    Map<String, dynamic>? body,
  }) async {
    pathDiterima = path;
    bodyDiterima = body;
    if (path.endsWith('/reset-pin')) return {};
    return {
      'id': 'pengguna-baru',
      'toko_id': 'toko-1',
      'role_id': body!['role_id'],
      'nama': body['nama'],
      'no_hp': null,
      'aktif': true,
      'outlet_ids': body['outlet_ids'],
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
      'id': 'pengguna-1',
      'toko_id': 'toko-1',
      'role_id': body['role_id'],
      'nama': body['nama'],
      'no_hp': null,
      'aktif': body['aktif'],
      'outlet_ids': body['outlet_ids'],
    };
  }

  @override
  Future<void> deleteJson({required String accessToken, required String path}) async {
    pathDiterima = path;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  testWidgets('tambah pengguna baru - isi form lalu simpan terkirim ke backend', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final fakeBackend = _FakeBackendApiPengguna();

    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWith((ref) => db),
        authSessionStoreProvider.overrideWithValue(_FakeAuthSessionStoreTerisi()),
        backendApiProvider.overrideWithValue(fakeBackend),
        isOnlineProvider.overrideWith((ref) => Stream.value(true)),
      ],
      child: _bungkusRouter(const PenggunaFormPage()),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('penggunaForm.nama')), 'Ani');
    await tester.tap(find.byKey(const Key('penggunaForm.role')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kasir').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('penggunaForm.pin')), '123456');
    await tester.tap(find.byKey(const Key('penggunaForm.outlet.outlet-1')));
    await tester.tap(find.byKey(const Key('penggunaForm.simpan')));
    await tester.pumpAndSettle();

    expect(fakeBackend.pathDiterima, '/pengguna');
    expect(fakeBackend.bodyDiterima!['nama'], 'Ani');
    expect(fakeBackend.bodyDiterima!['outlet_ids'], ['outlet-1']);

    final rows = await db.select(db.pengguna).get();
    expect(rows.single.nama, 'Ani');
    expect(rows.single.serverPenggunaId, 'pengguna-baru');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('validasi - nama kosong menampilkan error, tidak memanggil backend', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final fakeBackend = _FakeBackendApiPengguna();

    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWith((ref) => db),
        authSessionStoreProvider.overrideWithValue(_FakeAuthSessionStoreTerisi()),
        backendApiProvider.overrideWithValue(fakeBackend),
        isOnlineProvider.overrideWith((ref) => Stream.value(true)),
      ],
      child: _bungkusRouter(const PenggunaFormPage()),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('penggunaForm.pin')), '123456');
    await tester.tap(find.byKey(const Key('penggunaForm.simpan')));
    await tester.pumpAndSettle();

    expect(find.text('Nama wajib diisi'), findsOneWidget);
    expect(fakeBackend.pathDiterima, isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('kondisi offline - banner tampil & tombol simpan nonaktif', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final fakeBackend = _FakeBackendApiPengguna();

    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWith((ref) => db),
        authSessionStoreProvider.overrideWithValue(_FakeAuthSessionStoreTerisi()),
        backendApiProvider.overrideWithValue(fakeBackend),
        isOnlineProvider.overrideWith((ref) => Stream.value(false)),
      ],
      child: _bungkusRouter(const PenggunaFormPage()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Butuh internet untuk mengubah pengaturan'), findsOneWidget);
    final tombol = tester.widget<FilledButton>(find.descendant(
      of: find.byKey(const Key('penggunaForm.simpan')),
      matching: find.byType(FilledButton),
    ));
    expect(tombol.onPressed, isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('mode edit - ubah nama & akses outlet terkirim lewat PATCH', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final fakeBackend = _FakeBackendApiPengguna();
    final penggunaEdit = {
      'id': 'pengguna-1',
      'toko_id': 'toko-1',
      'role_id': 'role-kasir',
      'nama': 'Budi',
      'no_hp': null,
      'aktif': true,
      'outlet_ids': <String>[],
    };

    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWith((ref) => db),
        authSessionStoreProvider.overrideWithValue(_FakeAuthSessionStoreTerisi()),
        backendApiProvider.overrideWithValue(fakeBackend),
        isOnlineProvider.overrideWith((ref) => Stream.value(true)),
      ],
      child: _bungkusRouter(PenggunaFormPage(penggunaEdit: penggunaEdit)),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Ubah Pengguna'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('penggunaForm.nama')), 'Budi Updated');
    await tester.tap(find.byKey(const Key('penggunaForm.outlet.outlet-1')));
    await tester.tap(find.byKey(const Key('penggunaForm.simpan')));
    await tester.pumpAndSettle();

    expect(fakeBackend.pathDiterima, '/pengguna/pengguna-1');
    expect(fakeBackend.bodyDiterima!['nama'], 'Budi Updated');
    expect(fakeBackend.bodyDiterima!['outlet_ids'], ['outlet-1']);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
