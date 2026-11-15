import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/core/network/auth_session_store.dart';
import 'package:apps_pos/core/network/backend_api.dart';
import 'package:apps_pos/core/network/connectivity_provider.dart';
import 'package:apps_pos/core/network/dio_backend_api.dart';
import 'package:apps_pos/core/providers/database_provider.dart';
import 'package:apps_pos/features/promo/data/local/tables/pajak_table.dart' show PajakTipe;
import 'package:apps_pos/features/promo/domain/pajak.dart';
import 'package:apps_pos/features/promo/domain/status_pajak_usaha.dart';
import 'package:apps_pos/features/promo/presentation/pages/pajak_form_page.dart';
import 'package:apps_pos/features/promo/presentation/pages/pajak_list_page.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _Sesi extends AuthSessionStore {
  _Sesi() : super(const FlutterSecureStorage());

  @override
  Future<SesiBackend?> muat() async => const SesiBackend(
        accessToken: 'token',
        refreshToken: 'refresh',
        tokoId: 'toko-default',
        outletId: 'outlet-1',
        penggunaId: 'pengguna-1',
        perangkatId: 'perangkat-1',
      );
}

class _FakeApi implements BackendApi {
  final patchDiterima = <String, Map<String, dynamic>>{};
  Map<String, dynamic>? postBody;

  @override
  Future<dynamic> patchJson({required String accessToken, required String path, required Map<String, dynamic> body}) async {
    patchDiterima[path] = body;
    return {'id': path.split('/').last, ...body};
  }

  @override
  Future<dynamic> postJson({required String accessToken, required String path, Map<String, dynamic>? body}) async {
    postBody = body;
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
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Pajak _p(String id, PajakTipe tipe, {bool aktif = true}) =>
    Pajak(id: id, tokoId: 't', nama: id, tipe: tipe, persen: 10, termasukHarga: false, urutan: 0, aktif: aktif);

Future<void> _tambah(AppDatabase db, String id, String nama, PajakTipe tipe, {bool aktif = true}) =>
    db.pajakDao.upsertPajak(PajakCompanion.insert(
      id: id,
      tokoId: 'toko-default',
      nama: nama,
      tipe: Value(tipe),
      persen: 10,
      aktif: Value(aktif),
      createdAt: 0,
      updatedAt: 0,
    ));

void main() {
  group('statusPajakUsaha', () {
    test('belum ada pajak sama sekali: belum diatur', () => expect(statusPajakUsaha([]), StatusPajakUsaha.belumDiatur));

    test('hanya service charge: belum diatur (service tidak dihitung)', () {
      expect(statusPajakUsaha([_p('s', PajakTipe.service)]), StatusPajakUsaha.belumDiatur);
    });

    test('ada pajak aktif: kena pajak', () {
      expect(statusPajakUsaha([_p('a', PajakTipe.pajak), _p('s', PajakTipe.service)]), StatusPajakUsaha.kena);
    });

    test('semua pajak nonaktif walau service aktif: tidak kena pajak', () {
      expect(
        statusPajakUsaha([_p('a', PajakTipe.pajak, aktif: false), _p('s', PajakTipe.service)]),
        StatusPajakUsaha.tidakKena,
      );
    });
  });

  test('preset: PB1 10%, PPN 11%, Service 5% dengan tipe yang benar', () {
    final peta = {for (final p in daftarPresetPajak) p.nama: p};
    expect(peta['PB1']!.persen, 10);
    expect(peta['PB1']!.tipe, PajakTipe.pajak);
    expect(peta['PPN']!.persen, 11);
    expect(peta['Service']!.tipe, PajakTipe.service);
    expect(peta['Service']!.persen, 5);
  });

  testWidgets('form tambah: pilihan cepat PB1 mengisi nama, persen, tipe lalu tersimpan', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final api = _FakeApi();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWith((ref) => db),
        authSessionStoreProvider.overrideWithValue(_Sesi()),
        backendApiProvider.overrideWithValue(api),
        isOnlineProvider.overrideWith((ref) => Stream.value(true)),
      ],
      child: MaterialApp.router(
        routerConfig: GoRouter(initialLocation: '/form', routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(body: SizedBox()),
            routes: [GoRoute(path: 'form', builder: (_, _) => const PajakFormPage())],
          ),
        ]),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('pajakForm.preset.PB1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pajakForm.simpan')));
    await tester.pumpAndSettle();

    expect(api.postBody!['nama'], 'PB1');
    expect(api.postBody!['persen'], '10');
    expect(api.postBody!['tipe'], 'pajak');
    expect(api.postBody!['termasuk_harga'], false);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('daftar: saklar Usaha kena pajak mematikan/menyalakan pajak, service charge tidak tersentuh', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _tambah(db, 'pb1', 'PB1', PajakTipe.pajak);
    await _tambah(db, 'ppn', 'PPN', PajakTipe.pajak);
    await _tambah(db, 'svc', 'Service', PajakTipe.service);
    final api = _FakeApi();

    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWith((ref) => db),
        authSessionStoreProvider.overrideWithValue(_Sesi()),
        backendApiProvider.overrideWithValue(api),
        isOnlineProvider.overrideWith((ref) => Stream.value(true)),
      ],
      child: const MaterialApp(home: PajakListPage()),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('pajakList.statusUsaha')), findsOneWidget);
    expect(find.text('Pajak diterapkan pada transaksi.'), findsOneWidget);

    // Matikan: hanya dua baris bertipe pajak yang dikirim ke server.
    await tester.tap(find.byKey(const Key('pajakList.saklarKenaPajak')));
    await tester.pumpAndSettle();
    expect(api.patchDiterima.keys.toSet(), {'/pajak/pb1', '/pajak/ppn'});
    expect(api.patchDiterima.values.every((b) => b['aktif'] == false), isTrue);
    expect(find.textContaining('Tidak kena pajak'), findsOneWidget);
    expect(find.text('Nonaktif'), findsNWidgets(2));
    final rows = {for (final r in await db.select(db.pajak).get()) r.id: r.aktif};
    expect(rows, {'pb1': false, 'ppn': false, 'svc': true});

    // Nyalakan lagi: dua baris pajak aktif kembali.
    api.patchDiterima.clear();
    await tester.tap(find.byKey(const Key('pajakList.saklarKenaPajak')));
    await tester.pumpAndSettle();
    expect(api.patchDiterima.keys.toSet(), {'/pajak/pb1', '/pajak/ppn'});
    expect(find.text('Pajak diterapkan pada transaksi.'), findsOneWidget);
    expect({for (final r in await db.select(db.pajak).get()) r.id: r.aktif}, {'pb1': true, 'ppn': true, 'svc': true});

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('daftar: tanpa pajak (hanya service) saklar tidak tampil', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _tambah(db, 'svc', 'Service', PajakTipe.service);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWith((ref) => db),
        authSessionStoreProvider.overrideWithValue(_Sesi()),
        isOnlineProvider.overrideWith((ref) => Stream.value(true)),
      ],
      child: const MaterialApp(home: PajakListPage()),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pajakList.statusUsaha')), findsNothing);
    expect(find.text('Service'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
