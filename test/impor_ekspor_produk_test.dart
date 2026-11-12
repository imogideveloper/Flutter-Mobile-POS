import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/core/network/auth_session_store.dart';
import 'package:apps_pos/core/network/backend_api.dart';
import 'package:apps_pos/core/network/backend_exception.dart';
import 'package:apps_pos/core/network/dio_backend_api.dart';
import 'package:apps_pos/features/produk/data/local/tables/produk_table.dart';
import 'package:apps_pos/features/produk/domain/produk_csv.dart';
import 'package:apps_pos/features/produk/presentation/pages/impor_ekspor_produk_page.dart';
import 'package:apps_pos/features/produk/presentation/providers/impor_produk_providers.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:apps_pos/core/network/connectivity_provider.dart';
import 'package:apps_pos/core/providers/database_provider.dart';
import 'package:apps_pos/core/providers/session_provider.dart';
import 'package:apps_pos/core/providers/toko_profile_provider.dart';

class _Sesi extends AuthSessionStore {
  _Sesi() : super(const FlutterSecureStorage());

  @override
  Future<SesiBackend?> muat() async => const SesiBackend(
        accessToken: 't',
        refreshToken: 'r',
        tokoId: 'toko-default',
        outletId: 'outlet',
        penggunaId: 'u',
        perangkatId: 'p',
      );
}

class _LoginOwner extends PenggunaSessionNotifier {
  @override
  String? build() => 'pengguna-default';
}

class _Api implements BackendApi {
  _Api({this.offline = false});

  final bool offline;
  final List<({List<Map<String, dynamic>> baris, bool simulasi})> panggilan = [];

  @override
  Future<Map<String, dynamic>> imporProduk({
    required String accessToken,
    required List<Map<String, dynamic>> baris,
    required bool simulasi,
  }) async {
    if (offline) throw const BackendException(message: 'x');
    panggilan.add((baris: baris, simulasi: simulasi));
    return {
      'simulasi': simulasi,
      'diterima': baris.length - 1,
      'ditolak': 1,
      'kategori_baru': ['Minuman'],
      'hasil': [
        {'nomor': 1, 'nama': baris.first['nama'], 'status': 'ditolak', 'pesan': 'SKU KS-1 sudah dipakai'},
        for (var i = 1; i < baris.length; i++) {'nomor': i + 1, 'nama': baris[i]['nama'], 'status': 'diterima'},
      ],
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late AppDatabase db;
  late _Api api;
  String? isiCsv;
  Object? galatPilih;
  final dibagikan = <(String, String)>[];

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    api = _Api();
    isiCsv = null;
    galatPilih = null;
    dibagikan.clear();
    await db.fiturDao.simpanStatusFitur(
      tokoId: 'toko-default',
      paket: 'Pro',
      kodeFiturAktif: const ['catalog_export', 'ekspor_impor'],
      batasPerKode: const {},
      updatedAt: 0,
    );
  });

  tearDown(() => db.close());

  Future<void> buka(WidgetTester tester, {_Api? apiPakai}) async {
    tester.view.physicalSize = const Size(900, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWith((ref) => db),
        currentPenggunaIdProvider.overrideWith(_LoginOwner.new),
        tokoProfileProvider.overrideWith((ref) async => null),
        isOnlineProvider.overrideWith((ref) => Stream.value(true)),
        authSessionStoreProvider.overrideWithValue(_Sesi()),
        backendApiProvider.overrideWithValue(apiPakai ?? api),
        pemilihCsvProvider.overrideWithValue(() async {
          if (galatPilih != null) throw galatPilih!;
          return isiCsv;
        }),
        pembagiBerkasProvider.overrideWithValue((nama, isi) async => dibagikan.add((nama, isi))),
      ],
      child: const MaterialApp(home: ImporEksporProdukPage()),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> tutup(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('membagikan template CSV yang bisa dibaca kembali', (tester) async {
    await buka(tester);
    await tester.tap(find.byKey(const Key('impor.template')));
    await tester.pumpAndSettle();
    expect(dibagikan.single.$1, 'template_produk.csv');
    expect(bacaCsvProduk(dibagikan.single.$2).siap.length, 2);
    await tutup(tester);
  });

  testWidgets('pilih berkas: ringkasan menunjukkan baris siap dan bermasalah beserta alasannya', (tester) async {
    isiCsv = 'nama,kategori,harga_jual\nKopi Susu,Minuman,18000\n,Minuman,5000\nTeh,Minuman,abc\nRoti,Makanan,15.000\n';
    await buka(tester);
    await tester.tap(find.byKey(const Key('impor.pilih')));
    await tester.pumpAndSettle();
    expect(find.text('2 produk siap diimpor, 2 baris bermasalah'), findsOneWidget);
    expect(find.textContaining('Baris 3: Nama produk kosong'), findsOneWidget);
    expect(find.textContaining('Baris 4: Harga jual'), findsOneWidget);
    expect(find.text('Impor 2 produk'), findsOneWidget);
    await tutup(tester);
  });

  testWidgets('Periksa dulu mengirim simulasi; Impor mengirim hanya baris valid dan menampilkan hasil', (tester) async {
    isiCsv = 'nama,sku,harga_jual\nKopi Susu,KS-1,18000\nTeh,,abc\nRoti,,15000\nAir,,3000\n';
    await buka(tester);
    await tester.tap(find.byKey(const Key('impor.pilih')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('impor.periksa')));
    await tester.pumpAndSettle();
    expect(api.panggilan.single.simulasi, isTrue);
    expect(api.panggilan.single.baris.map((b) => b['nama']), ['Kopi Susu', 'Roti', 'Air'],
        reason: 'baris rusak tidak dikirim');
    expect(find.textContaining('belum disimpan'), findsOneWidget);
    expect(find.textContaining('KS-1 sudah dipakai'), findsOneWidget);

    await tester.tap(find.byKey(const Key('impor.simpan')));
    await tester.pumpAndSettle();
    expect(api.panggilan.length, 2);
    expect(api.panggilan.last.simulasi, isFalse);
    expect(find.text('Hasil impor: 2 disimpan, 1 ditolak'), findsOneWidget);
    expect(find.text('Kategori baru: Minuman'), findsOneWidget);
    await tutup(tester);
  });

  testWidgets('berkas rusak, terlalu besar, dan dibatalkan', (tester) async {
    isiCsv = 'harga,hpp\n1,2\n';
    await buka(tester);
    await tester.tap(find.byKey(const Key('impor.pilih')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Kolom "nama" tidak ditemukan'), findsOneWidget);
    expect(find.byKey(const Key('impor.simpan')), findsNothing);

    galatPilih = const FormatException('Berkas terlalu besar (maksimal 1 MB).');
    await tester.tap(find.byKey(const Key('impor.pilih')));
    await tester.pumpAndSettle();
    expect(find.textContaining('terlalu besar'), findsOneWidget);

    galatPilih = null;
    isiCsv = null; // pengguna membatalkan pemilih
    await tester.tap(find.byKey(const Key('impor.pilih')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('impor.error')), findsNothing);
    await tutup(tester);
  });

  testWidgets('offline: pesan butuh internet dan tidak ada hasil', (tester) async {
    isiCsv = 'nama\nKopi\n';
    await buka(tester, apiPakai: _Api(offline: true));
    await tester.tap(find.byKey(const Key('impor.pilih')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('impor.simpan')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Butuh internet'), findsOneWidget);
    expect(find.byKey(const Key('impor.hasil')), findsNothing);
    await tutup(tester);
  });

  testWidgets('ekspor membagikan semua produk lengkap dengan nama kategori', (tester) async {
    await db.produkDao.upsertKategori(KategoriCompanion.insert(
        id: 'k1', tokoId: 'toko-default', nama: 'Minuman', createdAt: 1, updatedAt: 1));
    await db.produkDao.upsertProduk(ProdukCompanion.insert(
      id: 'p1',
      tokoId: 'toko-default',
      kategoriId: const Value('k1'),
      nama: 'Kopi Susu',
      sku: const Value('KS-1'),
      tipe: ProdukTipe.barang,
      hargaJual: const Value(18000),
      hpp: const Value(7000),
      createdAt: 1,
      updatedAt: 1,
    ));
    await buka(tester);
    await tester.tap(find.byKey(const Key('impor.ekspor')));
    // Kueri stream drift memakai timer: beri waktu nyata agar selesai di luar FakeAsync.
    for (var i = 0; i < 20 && dibagikan.isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
    expect(dibagikan.single.$1, 'produk.csv');
    final balik = bacaCsvProduk(dibagikan.single.$2).baris.single;
    expect(balik.nama, 'Kopi Susu');
    expect(balik.kategori, 'Minuman');
    expect(balik.hargaJual, 18000);
    expect(balik.hpp, 7000);
    expect(balik.sku, 'KS-1');
    await tutup(tester);
  });
}
