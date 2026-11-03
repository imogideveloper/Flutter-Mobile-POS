import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/core/network/auth_session_store.dart';
import 'package:apps_pos/core/network/backend_api.dart';
import 'package:apps_pos/core/network/connectivity_provider.dart';
import 'package:apps_pos/core/network/dio_backend_api.dart';
import 'package:apps_pos/core/providers/database_provider.dart';
import 'package:apps_pos/features/promo/data/local/tables/promo_table.dart' show PromoCakupan, PromoTipe;
import 'package:apps_pos/features/promo/domain/promo.dart';
import 'package:apps_pos/features/promo/presentation/pages/promo_form_page.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// PromoFormPage memanggil context.pop() dari go_router - lihat catatan
/// memori feedback-flutter-test-hangs/_bungkusRouter di pajak_form_flow_test.dart.
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

class _FakeBackendApiPromo implements BackendApi {
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
      'id': 'promo-baru',
      'nama': body!['nama'],
      'kode': body['kode'],
      'tipe': body['tipe'],
      'nilai': body['nilai'],
      'cakupan': body['cakupan'],
      'min_belanja': body['min_belanja'],
      'maks_diskon': body['maks_diskon'],
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
      'id': 'promo-1',
      'nama': body['nama'],
      'kode': body['kode'],
      'tipe': body['tipe'],
      'nilai': body['nilai'],
      'cakupan': body['cakupan'],
      'min_belanja': body['min_belanja'],
      'maks_diskon': body['maks_diskon'],
      'aktif': body['aktif'],
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  testWidgets('tambah promo baru - isi form lalu simpan terkirim ke backend', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final fakeBackend = _FakeBackendApiPromo();

    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWith((ref) => db),
        authSessionStoreProvider.overrideWithValue(_FakeAuthSessionStoreTerisi()),
        backendApiProvider.overrideWithValue(fakeBackend),
        isOnlineProvider.overrideWith((ref) => Stream.value(true)),
      ],
      child: _bungkusRouter(const PromoFormPage()),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('promoForm.nama')), 'Promo Jumat');
    await tester.enterText(find.byKey(const Key('promoForm.nilai')), '10');
    await tester.drag(find.byKey(const Key('promoForm.scrollView')), const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('promoForm.simpan')));
    await tester.pumpAndSettle();

    expect(fakeBackend.pathDiterima, '/promo');
    expect(fakeBackend.bodyDiterima!['nama'], 'Promo Jumat');

    final rows = await db.select(db.promo).get();
    expect(rows.single.nama, 'Promo Jumat');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('validasi - nilai kosong menampilkan error, tidak memanggil backend', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final fakeBackend = _FakeBackendApiPromo();

    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWith((ref) => db),
        authSessionStoreProvider.overrideWithValue(_FakeAuthSessionStoreTerisi()),
        backendApiProvider.overrideWithValue(fakeBackend),
        isOnlineProvider.overrideWith((ref) => Stream.value(true)),
      ],
      child: _bungkusRouter(const PromoFormPage()),
    ));
    await tester.pumpAndSettle();
    await tester.drag(find.byKey(const Key('promoForm.scrollView')), const Offset(0, -400));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('promoForm.nama')), 'Promo Jumat');
    await tester.tap(find.byKey(const Key('promoForm.simpan')));
    await tester.pumpAndSettle();

    expect(find.text('Nilai wajib diisi'), findsOneWidget);
    expect(fakeBackend.pathDiterima, isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('kondisi offline - banner tampil & tombol simpan nonaktif', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final fakeBackend = _FakeBackendApiPromo();

    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWith((ref) => db),
        authSessionStoreProvider.overrideWithValue(_FakeAuthSessionStoreTerisi()),
        backendApiProvider.overrideWithValue(fakeBackend),
        isOnlineProvider.overrideWith((ref) => Stream.value(false)),
      ],
      child: _bungkusRouter(const PromoFormPage()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Butuh internet untuk mengubah pengaturan'), findsOneWidget);
    final tombol = tester.widget<FilledButton>(find.descendant(
      of: find.byKey(const Key('promoForm.simpan')),
      matching: find.byType(FilledButton),
    ));
    expect(tombol.onPressed, isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('mode edit - ubah nilai lalu kirim PATCH', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final fakeBackend = _FakeBackendApiPromo();
    const promoLama = Promo(
      id: 'promo-1',
      tokoId: 'toko-1',
      nama: 'Promo Lama',
      tipe: PromoTipe.persen,
      nilai: 5,
      cakupan: PromoCakupan.transaksi,
      minBelanja: 0,
      aktif: true,
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWith((ref) => db),
        authSessionStoreProvider.overrideWithValue(_FakeAuthSessionStoreTerisi()),
        backendApiProvider.overrideWithValue(fakeBackend),
        isOnlineProvider.overrideWith((ref) => Stream.value(true)),
      ],
      child: _bungkusRouter(PromoFormPage(promoEdit: promoLama)),
    ));
    await tester.drag(find.byKey(const Key('promoForm.scrollView')), const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();

    expect(find.text('Ubah Promo'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('promoForm.nilai')), '15');
    await tester.tap(find.byKey(const Key('promoForm.simpan')));
    await tester.pumpAndSettle();

    expect(fakeBackend.pathDiterima, '/promo/promo-1');
    expect(fakeBackend.bodyDiterima!['nilai'], '15');
    expect(fakeBackend.bodyDiterima!['aktif'], true);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
