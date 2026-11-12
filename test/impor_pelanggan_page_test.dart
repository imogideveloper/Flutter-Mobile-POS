import 'package:apps_pos/core/network/auth_session_store.dart';
import 'package:apps_pos/core/network/backend_api.dart';
import 'package:apps_pos/core/network/backend_exception.dart';
import 'package:apps_pos/core/network/dio_backend_api.dart';
import 'package:apps_pos/features/pelanggan/domain/pelanggan_csv.dart';
import 'package:apps_pos/features/pelanggan/presentation/pages/impor_pelanggan_page.dart';
import 'package:apps_pos/features/produk/presentation/providers/impor_produk_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _Sesi extends AuthSessionStore {
  _Sesi() : super(const FlutterSecureStorage());

  @override
  Future<SesiBackend?> muat() async => const SesiBackend(
        accessToken: 't',
        refreshToken: 'r',
        tokoId: 'toko',
        outletId: 'outlet',
        penggunaId: 'u',
        perangkatId: 'p',
      );
}

class _Api implements BackendApi {
  _Api({this.offline = false, this.statusGagal});

  final bool offline;
  final int? statusGagal;
  final List<({List<Map<String, dynamic>> baris, bool simulasi})> panggilan = [];

  @override
  Future<Map<String, dynamic>> imporPelanggan({
    required String accessToken,
    required List<Map<String, dynamic>> baris,
    required bool simulasi,
  }) async {
    if (offline) throw const BackendException(message: 'x');
    if (statusGagal != null) throw BackendException(message: 'ditolak', statusCode: statusGagal);
    panggilan.add((baris: baris, simulasi: simulasi));
    return {
      'simulasi': simulasi,
      'diterima': baris.length - 1,
      'ditolak': 1,
      'hasil': [
        {'nomor': 1, 'nama': baris.first['nama'], 'status': 'ditolak', 'pesan': 'Nomor HP 0812 sudah terdaftar'},
        for (var i = 1; i < baris.length; i++) {'nomor': i + 1, 'nama': baris[i]['nama'], 'status': 'diterima'},
      ],
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  String? isiCsv;
  Object? galatPilih;
  final dibagikan = <(String, String)>[];

  setUp(() {
    isiCsv = null;
    galatPilih = null;
    dibagikan.clear();
  });

  Future<void> buka(WidgetTester tester, _Api api) async {
    tester.view.physicalSize = const Size(900, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        backendApiProvider.overrideWithValue(api),
        authSessionStoreProvider.overrideWithValue(_Sesi()),
        pemilihCsvProvider.overrideWithValue(() async {
          if (galatPilih != null) throw galatPilih!;
          return isiCsv;
        }),
        pembagiBerkasProvider.overrideWithValue((nama, isi) async => dibagikan.add((nama, isi))),
      ],
      child: const MaterialApp(home: ImporPelangganPage()),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> tutup(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('membagikan template yang bisa dibaca kembali', (tester) async {
    await buka(tester, _Api());
    await tester.tap(find.byKey(const Key('imporPelanggan.template')));
    await tester.pumpAndSettle();
    expect(dibagikan.single.$1, 'template_pelanggan.csv');
    expect(bacaCsvPelanggan(dibagikan.single.$2).siap.length, 2);
    await tutup(tester);
  });

  testWidgets('ringkasan menunjukkan baris siap dan bermasalah beserta alasannya', (tester) async {
    isiCsv = 'nama,no_hp,tanggal_lahir\nSari,081200000001,1995-04-12\n,081200000002,\nBudi,81234567890,kemarin\n';
    await buka(tester, _Api());
    await tester.tap(find.byKey(const Key('imporPelanggan.pilih')));
    await tester.pumpAndSettle();
    expect(find.text('1 pelanggan siap diimpor, 2 baris bermasalah'), findsOneWidget);
    expect(find.textContaining('Baris 3: Nama pelanggan kosong'), findsOneWidget);
    expect(find.textContaining('Baris 4: Tanggal lahir'), findsOneWidget);
    await tutup(tester);
  });

  testWidgets('Periksa dulu mengirim simulasi; Impor mengirim baris valid dengan nomor yang dinormalkan', (tester) async {
    isiCsv = 'nama,no_hp\nSari,81234567890\nBudi,081200000002\nAni,081200000003\nRusak,\n,0812\n';
    final api = _Api();
    await buka(tester, api);
    await tester.tap(find.byKey(const Key('imporPelanggan.pilih')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('imporPelanggan.periksa')));
    await tester.pumpAndSettle();
    expect(api.panggilan.single.simulasi, isTrue);
    expect(api.panggilan.single.baris.first['no_hp'], '081234567890', reason: 'angka 0 yang hilang dipulihkan');
    expect(find.textContaining('belum disimpan'), findsOneWidget);
    expect(find.textContaining('Nomor HP 0812 sudah terdaftar'), findsOneWidget);

    await tester.tap(find.byKey(const Key('imporPelanggan.simpan')));
    await tester.pumpAndSettle();
    expect(api.panggilan.last.simulasi, isFalse);
    expect(api.panggilan.last.baris.length, 4, reason: 'baris tanpa nama tidak dikirim');
    expect(find.text('Hasil impor: 3 disimpan, 1 ditolak'), findsOneWidget);
    await tutup(tester);
  });

  testWidgets('berkas rusak, terlalu besar, dan dibatalkan', (tester) async {
    isiCsv = 'no_hp\n0812\n';
    await buka(tester, _Api());
    await tester.tap(find.byKey(const Key('imporPelanggan.pilih')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Kolom "nama" tidak ditemukan'), findsOneWidget);
    expect(find.byKey(const Key('imporPelanggan.simpan')), findsNothing);

    galatPilih = const FormatException('Berkas terlalu besar (maksimal 1 MB).');
    await tester.tap(find.byKey(const Key('imporPelanggan.pilih')));
    await tester.pumpAndSettle();
    expect(find.textContaining('terlalu besar'), findsOneWidget);

    galatPilih = null;
    isiCsv = null;
    await tester.tap(find.byKey(const Key('imporPelanggan.pilih')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('imporPelanggan.error')), findsNothing);
    await tutup(tester);
  });

  testWidgets('offline dan paket terkunci (403) menampilkan pesan jelas', (tester) async {
    isiCsv = 'nama\nKopi\n';
    await buka(tester, _Api(offline: true));
    await tester.tap(find.byKey(const Key('imporPelanggan.pilih')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('imporPelanggan.simpan')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Butuh internet'), findsOneWidget);
    await tutup(tester);

    await buka(tester, _Api(statusGagal: 403));
    await tester.tap(find.byKey(const Key('imporPelanggan.pilih')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('imporPelanggan.simpan')));
    await tester.pumpAndSettle();
    expect(find.textContaining('belum bisa mengimpor'), findsOneWidget);
    await tutup(tester);
  });
}
