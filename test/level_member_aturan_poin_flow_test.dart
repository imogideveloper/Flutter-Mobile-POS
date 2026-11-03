import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/core/network/auth_session_store.dart';
import 'package:apps_pos/core/network/backend_api.dart';
import 'package:apps_pos/core/network/connectivity_provider.dart';
import 'package:apps_pos/core/network/dio_backend_api.dart';
import 'package:apps_pos/core/providers/database_provider.dart';
import 'package:apps_pos/features/fitur/presentation/providers/feature_gate_provider.dart';
import 'package:apps_pos/features/pelanggan/presentation/pages/level_member_aturan_poin_page.dart';
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
  Future<dynamic> postJson({
    required String accessToken,
    required String path,
    Map<String, dynamic>? body,
  }) async {
    pathDiterima = path;
    bodyDiterima = body;
    return {
      'id': 'level-baru',
      'nama': body!['nama'],
      'min_total_belanja': body['min_total_belanja'],
      'diskon_persen': body['diskon_persen'],
      'pengali_poin': body['pengali_poin'],
      'urutan': 0,
    };
  }

  @override
  Future<dynamic> putJsonBody({
    required String accessToken,
    required String path,
    required Map<String, dynamic> body,
  }) async {
    pathDiterima = path;
    bodyDiterima = body;
    return {
      'nominal_per_poin': body['nominal_per_poin'],
      'nilai_tukar_poin': body['nilai_tukar_poin'],
      'min_tukar_poin': body['min_tukar_poin'],
      'kedaluwarsa_hari': null,
      'aktif': body['aktif'],
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final _fiturTerbuka = featureGateProvider.overrideWith(
  (ref) async => const FeatureGate(paket: 'Bisnis', kodeAktif: {'diskon_member', 'poin_loyalitas'}, batas: {}),
);

void main() {
  testWidgets('tambah level member baru - isi form lalu simpan terkirim ke backend', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final fakeBackend = _FakeBackendApi();

    await tester.pumpWidget(ProviderScope(overrides: [
      _fiturTerbuka,
      appDatabaseProvider.overrideWith((ref) => db),
      authSessionStoreProvider.overrideWithValue(_FakeAuthSessionStoreTerisi()),
      backendApiProvider.overrideWithValue(fakeBackend),
      isOnlineProvider.overrideWith((ref) => Stream.value(true)),
    ], child: const MaterialApp(home: LevelMemberAturanPoinPage())));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('levelMemberPoin.tambahLevel')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('levelMemberDialog.nama')), 'Silver');
    await tester.tap(find.byKey(const Key('levelMemberDialog.simpan')));
    await tester.pumpAndSettle();

    expect(fakeBackend.pathDiterima, '/level-member');
    expect(fakeBackend.bodyDiterima!['nama'], 'Silver');

    final rows = await db.select(db.levelMember).get();
    expect(rows.single.nama, 'Silver');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('validasi - nama level kosong menampilkan error', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final fakeBackend = _FakeBackendApi();

    await tester.pumpWidget(ProviderScope(overrides: [
      _fiturTerbuka,
      appDatabaseProvider.overrideWith((ref) => db),
      authSessionStoreProvider.overrideWithValue(_FakeAuthSessionStoreTerisi()),
      backendApiProvider.overrideWithValue(fakeBackend),
      isOnlineProvider.overrideWith((ref) => Stream.value(true)),
    ], child: const MaterialApp(home: LevelMemberAturanPoinPage())));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('levelMemberPoin.tambahLevel')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('levelMemberDialog.simpan')));
    await tester.pumpAndSettle();

    expect(find.text('Nama wajib diisi'), findsOneWidget);
    expect(fakeBackend.pathDiterima, isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('kondisi offline - banner tampil & tombol simpan aturan poin nonaktif', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final fakeBackend = _FakeBackendApi();

    await tester.pumpWidget(ProviderScope(overrides: [
      _fiturTerbuka,
      appDatabaseProvider.overrideWith((ref) => db),
      authSessionStoreProvider.overrideWithValue(_FakeAuthSessionStoreTerisi()),
      backendApiProvider.overrideWithValue(fakeBackend),
      isOnlineProvider.overrideWith((ref) => Stream.value(false)),
    ], child: const MaterialApp(home: LevelMemberAturanPoinPage())));
    await tester.pumpAndSettle();

    expect(find.text('Butuh internet untuk mengubah pengaturan'), findsOneWidget);
    final tombol = tester.widget<FilledButton>(find.descendant(
      of: find.byKey(const Key('aturanPoinForm.simpan')),
      matching: find.byType(FilledButton),
    ));
    expect(tombol.onPressed, isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('aturan poin - isi form lalu simpan terkirim lewat PUT', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final fakeBackend = _FakeBackendApi();

    await tester.pumpWidget(ProviderScope(overrides: [
      _fiturTerbuka,
      appDatabaseProvider.overrideWith((ref) => db),
      authSessionStoreProvider.overrideWithValue(_FakeAuthSessionStoreTerisi()),
      backendApiProvider.overrideWithValue(fakeBackend),
      isOnlineProvider.overrideWith((ref) => Stream.value(true)),
    ], child: const MaterialApp(home: LevelMemberAturanPoinPage())));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('aturanPoinForm.nominalPerPoin')), '5000');
    await tester.ensureVisible(find.byKey(const Key('aturanPoinForm.simpan')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('aturanPoinForm.simpan')));
    await tester.pumpAndSettle();

    expect(fakeBackend.pathDiterima, '/aturan-poin');
    expect(fakeBackend.bodyDiterima!['nominal_per_poin'], '5000');

    final row = await (db.select(db.aturanPoin)..where((t) => t.tokoId.equals('toko-default'))).getSingle();
    expect(row.nominalPerPoin, 5000);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
