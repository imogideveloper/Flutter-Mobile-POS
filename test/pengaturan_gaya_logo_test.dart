import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/core/network/auth_session_store.dart';
import 'package:apps_pos/core/network/backend_api.dart';
import 'package:apps_pos/core/network/connectivity_provider.dart';
import 'package:apps_pos/core/network/dio_backend_api.dart';
import 'package:apps_pos/core/providers/database_provider.dart';
import 'package:apps_pos/core/providers/toko_profile_provider.dart';
import 'package:apps_pos/features/lainnya/presentation/pages/pengaturan_outlet_struk_page.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

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
  _FakeApi({this.gayaAwal = 'unggah'});

  final String gayaAwal;
  Map<String, dynamic>? bodyDikirim;

  @override
  Future<Map<String, dynamic>> ambilPengaturanOutlet({required String accessToken, required String outletId}) async => {
        'header_struk': null,
        'footer_struk': null,
        'lebar_kertas_mm': 58,
        'tampil_logo': true,
        'gaya_logo': gayaAwal,
        'struk_ringkas': false,
        'pakai_nomor_antrean': false,
        'antrean_awalan': 'A',
        'antrean_mulai': 1,
        'estimasi_menit': 0,
        'batas_margin': 50,
        'izinkan_stok_minus': true,
        'pembulatan': 0,
      };

  @override
  Future<Map<String, dynamic>> ubahPengaturanOutlet({
    required String accessToken,
    required String outletId,
    required Map<String, dynamic> body,
  }) async {
    bodyDikirim = body;
    return {...body, 'outlet_id': outletId};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  testWidgets('pilih gaya logo: pratinjau muncul, tersimpan ke server dan cache lokal', (tester) async {
    tester.view.physicalSize = const Size(900, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.fiturDao.simpanStatusFitur(
      tokoId: 'toko-default',
      paket: 'Bisnis',
      kodeFiturAktif: const ['logo_struk'],
      batasPerKode: const {},
      updatedAt: 0,
    );
    final api = _FakeApi();

    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWith((r) => db),
        authSessionStoreProvider.overrideWithValue(_Sesi()),
        backendApiProvider.overrideWithValue(api),
        isOnlineProvider.overrideWith((r) => Stream.value(true)),
        tokoProfileProvider.overrideWith(
          (r) async => const TokoProfile(namaToko: 'Kopi Senja', jenisUsaha: JenisUsaha.kafe, namaPemilik: 'Rina'),
        ),
      ],
      child: const MaterialApp(home: PengaturanOutletStrukPage()),
    ));
    await tester.pumpAndSettle();

    // Bawaan: logo unggahan, tanpa pratinjau gaya.
    expect(find.byKey(const Key('pengaturanOutletForm.gaya.unggah')), findsOneWidget);
    expect(find.byKey(const Key('pengaturanOutletForm.pratinjauGaya')), findsNothing);

    await tester.tap(find.byKey(const Key('pengaturanOutletForm.gaya.cincin')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pengaturanOutletForm.pratinjauGaya')), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('pengaturanOutletForm.simpan')));
    await tester.tap(find.byKey(const Key('pengaturanOutletForm.simpan')));
    await tester.pumpAndSettle();

    expect(api.bodyDikirim!['gaya_logo'], 'cincin');
    expect(api.bodyDikirim!['tampil_logo'], true);
    final lokal = await db.select(db.pengaturanOutlet).get();
    expect(lokal.single.gayaLogo, 'cincin');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('gaya tersimpan di server dimuat saat halaman dibuka', (tester) async {
    tester.view.physicalSize = const Size(900, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.fiturDao.simpanStatusFitur(
      tokoId: 'toko-default',
      paket: 'Bisnis',
      kodeFiturAktif: const ['logo_struk'],
      batasPerKode: const {},
      updatedAt: 0,
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWith((r) => db),
        authSessionStoreProvider.overrideWithValue(_Sesi()),
        backendApiProvider.overrideWithValue(_FakeApi(gayaAwal: 'inisial')),
        isOnlineProvider.overrideWith((r) => Stream.value(true)),
        tokoProfileProvider.overrideWith((r) async => null),
      ],
      child: const MaterialApp(home: PengaturanOutletStrukPage()),
    ));
    await tester.pumpAndSettle();

    final chip = tester.widget<ChoiceChip>(find.byKey(const Key('pengaturanOutletForm.gaya.inisial')));
    expect(chip.selected, isTrue);
    expect(find.byKey(const Key('pengaturanOutletForm.pratinjauGaya')), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
