import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/core/network/auth_session_store.dart';
import 'package:apps_pos/core/network/backend_api.dart';
import 'package:apps_pos/core/network/connectivity_provider.dart';
import 'package:apps_pos/core/network/dio_backend_api.dart';
import 'package:apps_pos/core/providers/database_provider.dart';
import 'package:apps_pos/features/fitur/presentation/providers/feature_gate_provider.dart';
import 'package:apps_pos/features/order/data/local/tables/tipe_order_table.dart' show TipeOrderKanal;
import 'package:apps_pos/features/order/presentation/pages/tipe_order_meja_page.dart';
import 'package:apps_pos/features/promo/data/local/tables/pajak_table.dart' show PajakTipe;
import 'package:drift/drift.dart' hide Column, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAuthSessionStoreTerisi extends AuthSessionStore {
  _FakeAuthSessionStoreTerisi() : super(const FlutterSecureStorage());

  @override
  Future<SesiBackend?> muat() async => const SesiBackend(
        accessToken: 'token',
        refreshToken: 'refresh',
        tokoId: 'toko-1',
        outletId: 'outlet-default',
        penggunaId: 'pengguna-1',
        perangkatId: 'perangkat-1',
      );
}

class _FakeBackendApi implements BackendApi {
  Map<String, dynamic>? bodyDiterima;
  String? pathDiterima;

  @override
  Future<dynamic> getJson({
    required String accessToken,
    required String path,
    Map<String, dynamic>? query,
  }) async {
    if (path.endsWith('/pajak')) return <Map<String, dynamic>>[];
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
    if (body == null) return {};
    if (path == '/tipe-order') {
      return {
        'id': 'tipe-order-baru',
        'nama': body['nama'],
        'kanal': body['kanal'],
        'pakai_meja': body['pakai_meja'],
        'markup_persen': '0',
        'urutan': 0,
        'aktif': true,
      };
    }
    return {
      'id': 'meja-baru',
      'nama': body['nama'],
      'area': body['area'],
      'kapasitas': body['kapasitas'],
      'urutan': 0,
      'aktif': true,
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
  testWidgets('tambah tipe pesanan baru - isi form lalu simpan terkirim ke backend', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final fakeBackend = _FakeBackendApi();

    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWith((ref) => db),
        authSessionStoreProvider.overrideWithValue(_FakeAuthSessionStoreTerisi()),
        backendApiProvider.overrideWithValue(fakeBackend),
        isOnlineProvider.overrideWith((ref) => Stream.value(true)),
        featureGateProvider.overrideWith(
          (ref) async => const FeatureGate(paket: 'Bisnis', kodeAktif: {'tipe_order'}, batas: {}),
        ),
      ],
      child: const MaterialApp(home: TipeOrderMejaPage()),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('tipeOrderMeja.tambahTipeOrder')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('tipeOrderDialog.nama')), 'Dine In');
    await tester.tap(find.byKey(const Key('tipeOrderDialog.simpan')));
    await tester.pumpAndSettle();

    expect(fakeBackend.pathDiterima, '/tipe-order');
    expect(fakeBackend.bodyDiterima!['nama'], 'Dine In');

    final rows = await db.select(db.tipeOrder).get();
    expect(rows.single.nama, 'Dine In');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('validasi - nama meja kosong menampilkan error', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final fakeBackend = _FakeBackendApi();

    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWith((ref) => db),
        authSessionStoreProvider.overrideWithValue(_FakeAuthSessionStoreTerisi()),
        backendApiProvider.overrideWithValue(fakeBackend),
        isOnlineProvider.overrideWith((ref) => Stream.value(true)),
        featureGateProvider.overrideWith(
          (ref) async => const FeatureGate(paket: 'Bisnis', kodeAktif: {'tipe_order'}, batas: {}),
        ),
      ],
      child: const MaterialApp(home: TipeOrderMejaPage()),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('tipeOrderMeja.tambahMeja')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('mejaDialog.simpan')));
    await tester.pumpAndSettle();

    expect(find.text('Nama wajib diisi'), findsOneWidget);
    expect(fakeBackend.pathDiterima, isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('kondisi offline - banner tampil & tombol simpan dialog nonaktif', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final fakeBackend = _FakeBackendApi();

    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWith((ref) => db),
        authSessionStoreProvider.overrideWithValue(_FakeAuthSessionStoreTerisi()),
        backendApiProvider.overrideWithValue(fakeBackend),
        isOnlineProvider.overrideWith((ref) => Stream.value(false)),
      ],
      child: const MaterialApp(home: TipeOrderMejaPage()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Butuh internet untuk mengubah pengaturan'), findsOneWidget);

    await tester.tap(find.byKey(const Key('tipeOrderMeja.tambahMeja')));
    await tester.pumpAndSettle();
    final tombol = tester.widget<FilledButton>(find.byKey(const Key('mejaDialog.simpan')));
    expect(tombol.onPressed, isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('tambah meja baru lalu hapus', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final fakeBackend = _FakeBackendApi();

    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWith((ref) => db),
        authSessionStoreProvider.overrideWithValue(_FakeAuthSessionStoreTerisi()),
        backendApiProvider.overrideWithValue(fakeBackend),
        isOnlineProvider.overrideWith((ref) => Stream.value(true)),
        featureGateProvider.overrideWith(
          (ref) async => const FeatureGate(paket: 'Bisnis', kodeAktif: {'tipe_order'}, batas: {}),
        ),
      ],
      child: const MaterialApp(home: TipeOrderMejaPage()),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('tipeOrderMeja.tambahMeja')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('mejaDialog.nama')), 'Meja 1');
    await tester.tap(find.byKey(const Key('mejaDialog.simpan')));
    await tester.pumpAndSettle();

    expect(find.text('Meja 1'), findsOneWidget);

    await tester.tap(find.text('Meja 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('mejaDialog.hapus')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Hapus'));
    await tester.pumpAndSettle();

    final rows = await (db.select(db.meja)..where((t) => t.aktif.equals(true))).get();
    expect(rows, isEmpty);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('service per tipe pesanan - centang service terkirim ke backend (POST link)', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.into(db.tipeOrder).insert(TipeOrderCompanion.insert(
          id: 'tipe-1',
          tokoId: 'toko-default',
          nama: 'Dine In',
          kanal: TipeOrderKanal.langsung,
          createdAt: now,
          updatedAt: now,
        ));
    // currentTokoIdProvider default 'toko-default' (tidak di-override -
    // NotifierProvider privat, lihat catatan di tes lain).
    await db.into(db.pajak).insert(PajakCompanion.insert(
          id: 'service-1',
          tokoId: 'toko-default',
          nama: 'Service Charge',
          tipe: const Value(PajakTipe.service),
          persen: 5,
          createdAt: now,
          updatedAt: now,
        ));
    final fakeBackend = _FakeBackendApi();

    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWith((ref) => db),
        authSessionStoreProvider.overrideWithValue(_FakeAuthSessionStoreTerisi()),
        backendApiProvider.overrideWithValue(fakeBackend),
        isOnlineProvider.overrideWith((ref) => Stream.value(true)),
        featureGateProvider.overrideWith(
          (ref) async => const FeatureGate(
            paket: 'Bisnis',
            kodeAktif: {'tipe_order', 'service_per_tipe_order'},
            batas: {},
          ),
        ),
      ],
      child: const MaterialApp(home: TipeOrderMejaPage()),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Dine In'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('tipeOrderDialog.service.service-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tipeOrderDialog.service.service-1')));
    await tester.pumpAndSettle();

    expect(fakeBackend.pathDiterima, '/tipe-order/tipe-1/pajak/service-1');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
