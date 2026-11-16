import 'dart:convert';
import 'dart:typed_data';

import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/core/network/auth_session_store.dart';
import 'package:apps_pos/core/network/backend_api.dart';
import 'package:apps_pos/core/network/connectivity_provider.dart';
import 'package:apps_pos/core/network/dio_backend_api.dart';
import 'package:apps_pos/core/providers/database_provider.dart';
import 'package:apps_pos/features/lainnya/presentation/pages/pengaturan_metode_bayar_page.dart';
import 'package:apps_pos/features/transaksi/presentation/providers/qris_providers.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

final _png = Uint8List.fromList(base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=='));

class _Sesi extends AuthSessionStore {
  _Sesi() : super(const FlutterSecureStorage());

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

class _FakeApi implements BackendApi {
  final hapusDipanggil = <String>[];

  @override
  Future<void> deleteJson({required String accessToken, required String path}) async => hapusDipanggil.add(path);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Future<AppDatabase> _siapkanDb() async {
  final db = AppDatabase(NativeDatabase.memory());
  await seedMetodeBayarUjiCoba(db);
  await db.fiturDao.simpanStatusFitur(
    tokoId: 'toko-default',
    paket: 'Pro',
    kodeFiturAktif: const ['qris'],
    batasPerKode: const {},
    updatedAt: 0,
  );
  return db;
}

Future<void> _bukaHalaman(WidgetTester tester, AppDatabase db, _FakeApi api, Uint8List? gambar) async {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWith((r) => db),
      authSessionStoreProvider.overrideWithValue(_Sesi()),
      backendApiProvider.overrideWithValue(api),
      isOnlineProvider.overrideWith((r) => Stream.value(true)),
      qrisTokoProvider.overrideWith((r) async => gambar),
    ],
    child: const MaterialApp(home: PengaturanMetodeBayarPage()),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('tombol gambar QRIS hanya ada pada metode QRIS; tanpa gambar dialog memberi petunjuk', (tester) async {
    final db = await _siapkanDb();
    addTearDown(db.close);
    await _bukaHalaman(tester, db, _FakeApi(), null);

    expect(find.byKey(const Key('pengaturanMetodeBayar.gambarQris.metode-qris-uji')), findsOneWidget);
    expect(find.byKey(const Key('pengaturanMetodeBayar.gambarQris.metode-tunai-uji')), findsNothing);
    expect(find.byKey(const Key('pengaturanMetodeBayar.gambarQris.metode-kartu-uji')), findsNothing);

    await tester.tap(find.byKey(const Key('pengaturanMetodeBayar.gambarQris.metode-qris-uji')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('gambarQris.kosong')), findsOneWidget);
    expect(find.byKey(const Key('gambarQris.pratinjau')), findsNothing);
    expect(find.byKey(const Key('gambarQris.hapus')), findsNothing);
    expect(find.text('Unggah'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('dengan gambar: pratinjau tampil dan Hapus memanggil DELETE /toko/qris', (tester) async {
    final db = await _siapkanDb();
    addTearDown(db.close);
    final api = _FakeApi();
    await _bukaHalaman(tester, db, api, _png);

    await tester.tap(find.byKey(const Key('pengaturanMetodeBayar.gambarQris.metode-qris-uji')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('gambarQris.pratinjau')), findsOneWidget);
    expect(find.text('Ganti'), findsOneWidget);

    await tester.tap(find.byKey(const Key('gambarQris.hapus')));
    await tester.pumpAndSettle();
    expect(api.hapusDipanggil, ['/toko/qris']);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
