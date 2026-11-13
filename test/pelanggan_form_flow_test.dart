import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/core/network/auth_session_store.dart';
import 'package:apps_pos/core/network/backend_api.dart';
import 'package:apps_pos/core/network/connectivity_provider.dart';
import 'package:apps_pos/core/network/dio_backend_api.dart';
import 'package:apps_pos/core/providers/database_provider.dart';
import 'package:apps_pos/features/pelanggan/domain/pelanggan.dart';
import 'package:apps_pos/features/pelanggan/presentation/pages/pelanggan_form_page.dart';
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
        outletId: 'outlet-1',
        penggunaId: 'pengguna-1',
        perangkatId: 'perangkat-1',
      );
}

class _FakeBackendApiPelanggan implements BackendApi {
  Map<String, dynamic>? bodyDiterima;
  String? pathDiterima;
  String? pathDihapus;

  @override
  Future<dynamic> postJson({
    required String accessToken,
    required String path,
    Map<String, dynamic>? body,
  }) async {
    pathDiterima = path;
    bodyDiterima = body;
    return {
      'id': 'pelanggan-baru',
      'nama': body!['nama'],
      'no_hp': body['no_hp'],
      'email': body['email'],
      'level_member_id': body['level_member_id'],
      'poin': 0,
      'total_belanja': '0',
      'batas_kasbon': body['batas_kasbon'],
      'catatan': body['catatan'],
      'tanggal_lahir': body['tanggal_lahir'],
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
      'id': 'pelanggan-1',
      'nama': body['nama'],
      'no_hp': body['no_hp'],
      'email': body['email'],
      'level_member_id': body['level_member_id'],
      'poin': 10,
      'total_belanja': '50000',
      'batas_kasbon': body['batas_kasbon'],
      'catatan': body['catatan'],
      'tanggal_lahir': body['tanggal_lahir'],
    };
  }

  @override
  Future<void> deleteJson({required String accessToken, required String path}) async {
    pathDihapus = path;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  Pelanggan sari({int? lahir}) => Pelanggan(
        id: 'pelanggan-1', tokoId: 't', nama: 'Sari', poin: 0, totalBelanja: 0, tanggalLahir: lahir,
      );

  Future<void> bukaEdit(WidgetTester tester, AppDatabase db, _FakeBackendApiPelanggan fake, Pelanggan p) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWith((ref) => db),
        authSessionStoreProvider.overrideWithValue(_FakeAuthSessionStoreTerisi()),
        backendApiProvider.overrideWithValue(fake),
        isOnlineProvider.overrideWith((ref) => Stream.value(true)),
      ],
      child: MaterialApp(home: PelangganFormPage(pelangganEdit: p)),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('tanggal lahir tersimpan dikirim sebagai ISO dan tersimpan di HP sebagai yyyymmdd', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final fake = _FakeBackendApiPelanggan();
    await bukaEdit(tester, db, fake, sari(lahir: 19950412));

    expect(find.text('Tanggal lahir: 1995-04-12'), findsOneWidget);
    await tester.tap(find.byKey(const Key('pelangganForm.simpan')));
    await tester.pumpAndSettle();

    expect(fake.bodyDiterima!['tanggal_lahir'], '1995-04-12');
    expect((await db.select(db.pelanggan).get()).single.tanggalLahir, 19950412);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('tanggal lahir dapat dihapus lalu dikirim null', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final fake = _FakeBackendApiPelanggan();
    await bukaEdit(tester, db, fake, sari(lahir: 19950412));

    await tester.tap(find.byKey(const Key('pelangganForm.hapusTanggalLahir')));
    await tester.pumpAndSettle();
    expect(find.text('Tanggal lahir (opsional)'), findsOneWidget);

    await tester.tap(find.byKey(const Key('pelangganForm.simpan')));
    await tester.pumpAndSettle();
    expect(fake.bodyDiterima!.containsKey('tanggal_lahir'), isTrue);
    expect(fake.bodyDiterima!['tanggal_lahir'], isNull);
    expect((await db.select(db.pelanggan).get()).single.tanggalLahir, isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('tambah pelanggan baru - isi form lalu simpan terkirim ke backend', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final fakeBackend = _FakeBackendApiPelanggan();

    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWith((ref) => db),
        authSessionStoreProvider.overrideWithValue(_FakeAuthSessionStoreTerisi()),
        backendApiProvider.overrideWithValue(fakeBackend),
        isOnlineProvider.overrideWith((ref) => Stream.value(true)),
      ],
      child: const MaterialApp(home: PelangganFormPage()),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('pelangganForm.nama')), 'Budi');
    await tester.tap(find.byKey(const Key('pelangganForm.simpan')));
    await tester.pumpAndSettle();

    expect(fakeBackend.pathDiterima, '/pelanggan');
    expect(fakeBackend.bodyDiterima!['nama'], 'Budi');

    final rows = await db.select(db.pelanggan).get();
    expect(rows.single.nama, 'Budi');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('validasi - nama kosong menampilkan error, tidak memanggil backend', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final fakeBackend = _FakeBackendApiPelanggan();

    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWith((ref) => db),
        authSessionStoreProvider.overrideWithValue(_FakeAuthSessionStoreTerisi()),
        backendApiProvider.overrideWithValue(fakeBackend),
        isOnlineProvider.overrideWith((ref) => Stream.value(true)),
      ],
      child: const MaterialApp(home: PelangganFormPage()),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('pelangganForm.simpan')));
    await tester.pumpAndSettle();

    expect(find.text('Nama wajib diisi'), findsOneWidget);
    expect(fakeBackend.pathDiterima, isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('kondisi offline - banner tampil & tombol simpan nonaktif', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final fakeBackend = _FakeBackendApiPelanggan();

    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWith((ref) => db),
        authSessionStoreProvider.overrideWithValue(_FakeAuthSessionStoreTerisi()),
        backendApiProvider.overrideWithValue(fakeBackend),
        isOnlineProvider.overrideWith((ref) => Stream.value(false)),
      ],
      child: const MaterialApp(home: PelangganFormPage()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Butuh internet untuk mengubah pengaturan'), findsOneWidget);
    final tombol = tester.widget<FilledButton>(find.descendant(
      of: find.byKey(const Key('pelangganForm.simpan')),
      matching: find.byType(FilledButton),
    ));
    expect(tombol.onPressed, isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('mode edit - hapus pelanggan setelah konfirmasi', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final fakeBackend = _FakeBackendApiPelanggan();
    const pelangganLama = Pelanggan(
      id: 'pelanggan-1',
      tokoId: 'toko-1',
      nama: 'Budi',
      poin: 10,
      totalBelanja: 50000,
    );

    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWith((ref) => db),
        authSessionStoreProvider.overrideWithValue(_FakeAuthSessionStoreTerisi()),
        backendApiProvider.overrideWithValue(fakeBackend),
        isOnlineProvider.overrideWith((ref) => Stream.value(true)),
      ],
      child: const MaterialApp(home: PelangganFormPage(pelangganEdit: pelangganLama)),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('pelangganForm.hapus')));
    await tester.pumpAndSettle();

    expect(find.text('Hapus pelanggan?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Hapus'));
    await tester.pumpAndSettle();

    expect(fakeBackend.pathDihapus, '/pelanggan/pelanggan-1');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
