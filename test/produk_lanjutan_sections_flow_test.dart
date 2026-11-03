import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/core/network/auth_session_store.dart';
import 'package:apps_pos/core/network/backend_api.dart';
import 'package:apps_pos/core/network/connectivity_provider.dart';
import 'package:apps_pos/core/network/dio_backend_api.dart';
import 'package:apps_pos/core/providers/database_provider.dart';
import 'package:apps_pos/features/fitur/presentation/providers/feature_gate_provider.dart';
import 'package:apps_pos/features/produk/data/local/tables/produk_table.dart' show ProdukTipe;
import 'package:apps_pos/features/produk/presentation/widgets/produk_lanjutan_sections.dart';
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
    if (path.endsWith('/resep')) return <Map<String, dynamic>>[];
    if (path.endsWith('/bundling')) return <Map<String, dynamic>>[];
    if (path.endsWith('/pajak')) return <Map<String, dynamic>>[];
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
    if (path.endsWith('/harga-grosir')) {
      return {'id': 'hg-baru', 'min_qty': body!['min_qty'], 'harga': body['harga']};
    }
    if (path.endsWith('/harga-outlet')) {
      return {'id': 'ho-baru', 'outlet_id': body!['outlet_id'], 'harga_jual': body['harga_jual']};
    }
    return {'id': 'baru'};
  }

  @override
  Future<dynamic> patchJson({
    required String accessToken,
    required String path,
    required Map<String, dynamic> body,
  }) async {
    pathDiterima = path;
    bodyDiterima = body;
    return {};
  }

  @override
  Future<void> deleteJson({required String accessToken, required String path}) async {
    pathDiterima = path;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final _fiturTerbuka = featureGateProvider.overrideWith(
  (ref) async => const FeatureGate(
    paket: 'Bisnis',
    kodeAktif: {'resep', 'bundling', 'harga_grosir', 'pajak_per_produk'},
    batas: {},
  ),
);

void main() {
  testWidgets('harga grosir - tambah tier baru terkirim ke backend & tercache lokal', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.into(db.produk).insert(ProdukCompanion.insert(
          id: 'produk-1',
          tokoId: 'toko-1',
          nama: 'Kopi Hitam',
          tipe: ProdukTipe.barang,
          createdAt: now,
          updatedAt: now,
        ));
    final fakeBackend = _FakeBackendApi();

    await tester.pumpWidget(ProviderScope(
      overrides: [
        _fiturTerbuka,
        appDatabaseProvider.overrideWith((ref) => db),
        authSessionStoreProvider.overrideWithValue(_FakeAuthSessionStoreTerisi()),
        backendApiProvider.overrideWithValue(fakeBackend),
        isOnlineProvider.overrideWith((ref) => Stream.value(true)),
      ],
      child: const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: ProdukLanjutanSections(produkId: 'produk-1'))),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('produkLanjutan.tambahHargaGrosir')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('hargaGrosirDialog.minQty')), '10');
    await tester.enterText(find.byKey(const Key('hargaGrosirDialog.harga')), '9000');
    await tester.tap(find.byKey(const Key('hargaGrosirDialog.simpan')));
    await tester.pumpAndSettle();

    expect(fakeBackend.pathDiterima, '/produk/produk-1/harga-grosir');
    expect(fakeBackend.bodyDiterima!['min_qty'], '10');

    final rows = await db.select(db.hargaGrosir).get();
    expect(rows.single.harga, 9000);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('validasi - harga grosir kosong menampilkan error', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.into(db.produk).insert(ProdukCompanion.insert(
          id: 'produk-1',
          tokoId: 'toko-1',
          nama: 'Kopi Hitam',
          tipe: ProdukTipe.barang,
          createdAt: now,
          updatedAt: now,
        ));
    final fakeBackend = _FakeBackendApi();

    await tester.pumpWidget(ProviderScope(
      overrides: [
        _fiturTerbuka,
        appDatabaseProvider.overrideWith((ref) => db),
        authSessionStoreProvider.overrideWithValue(_FakeAuthSessionStoreTerisi()),
        backendApiProvider.overrideWithValue(fakeBackend),
        isOnlineProvider.overrideWith((ref) => Stream.value(true)),
      ],
      child: const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: ProdukLanjutanSections(produkId: 'produk-1'))),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('produkLanjutan.tambahHargaGrosir')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('hargaGrosirDialog.simpan')));
    await tester.pumpAndSettle();

    expect(find.text('Wajib diisi'), findsWidgets);
    expect(fakeBackend.pathDiterima, isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('kondisi offline - banner tampil & tombol simpan harga outlet nonaktif', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.into(db.produk).insert(ProdukCompanion.insert(
          id: 'produk-1',
          tokoId: 'toko-1',
          nama: 'Kopi Hitam',
          tipe: ProdukTipe.barang,
          createdAt: now,
          updatedAt: now,
        ));
    final fakeBackend = _FakeBackendApi();

    await tester.pumpWidget(ProviderScope(
      overrides: [
        _fiturTerbuka,
        appDatabaseProvider.overrideWith((ref) => db),
        authSessionStoreProvider.overrideWithValue(_FakeAuthSessionStoreTerisi()),
        backendApiProvider.overrideWithValue(fakeBackend),
        isOnlineProvider.overrideWith((ref) => Stream.value(false)),
      ],
      child: const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: ProdukLanjutanSections(produkId: 'produk-1'))),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Butuh internet untuk mengubah pengaturan'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('produkLanjutan.tambahHargaOutlet')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('produkLanjutan.tambahHargaOutlet')));
    await tester.pumpAndSettle();
    final tombol = tester.widget<FilledButton>(find.byKey(const Key('hargaOutletDialog.simpan')));
    expect(tombol.onPressed, isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('harga outlet - pilih outlet lalu simpan terkirim ke backend', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.into(db.produk).insert(ProdukCompanion.insert(
          id: 'produk-1',
          tokoId: 'toko-1',
          nama: 'Kopi Hitam',
          tipe: ProdukTipe.barang,
          createdAt: now,
          updatedAt: now,
        ));
    final fakeBackend = _FakeBackendApi();

    await tester.pumpWidget(ProviderScope(
      overrides: [
        _fiturTerbuka,
        appDatabaseProvider.overrideWith((ref) => db),
        authSessionStoreProvider.overrideWithValue(_FakeAuthSessionStoreTerisi()),
        backendApiProvider.overrideWithValue(fakeBackend),
        isOnlineProvider.overrideWith((ref) => Stream.value(true)),
      ],
      child: const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: ProdukLanjutanSections(produkId: 'produk-1'))),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('produkLanjutan.tambahHargaOutlet')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('produkLanjutan.tambahHargaOutlet')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('hargaOutletDialog.outlet')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Outlet Pusat').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('hargaOutletDialog.harga')), '12000');
    await tester.tap(find.byKey(const Key('hargaOutletDialog.simpan')));
    await tester.pumpAndSettle();

    expect(fakeBackend.pathDiterima, '/produk/produk-1/harga-outlet');
    expect(fakeBackend.bodyDiterima!['outlet_id'], 'outlet-1');

    final rows = await db.select(db.hargaOutlet).get();
    expect(rows.single.hargaJual, 12000);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('pajak per produk - centang pajak terkirim ke backend (POST link)', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.into(db.produk).insert(ProdukCompanion.insert(
          id: 'produk-1',
          tokoId: 'toko-1',
          nama: 'Kopi Hitam',
          tipe: ProdukTipe.barang,
          createdAt: now,
          updatedAt: now,
        ));
    // currentTokoIdProvider tidak di-override (NotifierProvider privat) -
    // defaultnya 'toko-default', bukan 'toko-1' (dipakai di sesi backend
    // fake) - sama gotcha spt pajak_form_flow_test.dart.
    await db.into(db.pajak).insert(PajakCompanion.insert(
          id: 'pajak-1',
          tokoId: 'toko-default',
          nama: 'PPN',
          persen: 11,
          createdAt: now,
          updatedAt: now,
        ));
    final fakeBackend = _FakeBackendApi();

    await tester.pumpWidget(ProviderScope(
      overrides: [
        _fiturTerbuka,
        appDatabaseProvider.overrideWith((ref) => db),
        authSessionStoreProvider.overrideWithValue(_FakeAuthSessionStoreTerisi()),
        backendApiProvider.overrideWithValue(fakeBackend),
        isOnlineProvider.overrideWith((ref) => Stream.value(true)),
      ],
      child: const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: ProdukLanjutanSections(produkId: 'produk-1'))),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('produkPajak.pajak-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('produkPajak.pajak-1')));
    await tester.pumpAndSettle();

    expect(fakeBackend.pathDiterima, '/produk/produk-1/pajak/pajak-1');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
