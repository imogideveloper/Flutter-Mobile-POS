import 'package:apps_pos/core/network/auth_session_store.dart';
import 'package:apps_pos/core/network/backend_api.dart';
import 'package:apps_pos/core/network/backend_exception.dart';
import 'package:apps_pos/core/network/dio_backend_api.dart';
import 'package:apps_pos/features/absensi/domain/absensi_data.dart';
import 'package:apps_pos/features/absensi/presentation/pages/absensi_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

class _Sesi extends AuthSessionStore {
  _Sesi() : super(const FlutterSecureStorage());

  @override
  Future<SesiBackend?> muat() async => const SesiBackend(
        accessToken: 't',
        refreshToken: 'r',
        tokoId: 'toko',
        outletId: 'outlet-1',
        penggunaId: 'u',
        perangkatId: 'p',
      );
}

class _Api implements BackendApi {
  _Api({this.mulaiMasuk = false, this.statusGagal});

  bool mulaiMasuk;
  final int? statusGagal;
  final List<String> panggilan = [];
  String? outletDikirim;
  int? tzDikirim;

  Map<String, dynamic> _catatan({required bool keluar}) => {
        'id': 'a1',
        'pengguna_id': 'u',
        'pengguna_nama': 'Budi',
        'outlet_id': 'outlet-1',
        'jam_masuk': '2026-11-12T01:00:00+00:00',
        'jam_keluar': keluar ? '2026-11-12T03:15:00+00:00' : null,
        'durasi_menit': keluar ? 135 : null,
        'status': 'hadir',
        'catatan': null,
      };

  @override
  Future<Map<String, dynamic>> absensiSaya({required String accessToken}) async {
    if (statusGagal != null) throw BackendException(message: 'x', statusCode: statusGagal == -1 ? null : statusGagal);
    panggilan.add('saya');
    return {'aktif': mulaiMasuk ? _catatan(keluar: false) : null};
  }

  @override
  Future<Map<String, dynamic>> absenMasuk({required String accessToken, String? outletId, String? catatan}) async {
    panggilan.add('masuk');
    outletDikirim = outletId;
    mulaiMasuk = true;
    return _catatan(keluar: false);
  }

  @override
  Future<Map<String, dynamic>> absenKeluar({required String accessToken, String? catatan}) async {
    panggilan.add('keluar');
    mulaiMasuk = false;
    return _catatan(keluar: true);
  }

  @override
  Future<Map<String, dynamic>> daftarAbsensi({
    required String accessToken,
    required String dari,
    required String sampai,
    required int tzMenit,
  }) async {
    tzDikirim = tzMenit;
    return {
      'dari': dari,
      'sampai': sampai,
      'rekap': [
        {'pengguna_id': 'u', 'pengguna_nama': 'Budi', 'jumlah_hari': 2, 'total_menit': 135, 'masih_masuk': mulaiMasuk},
      ],
      'item': [_catatan(keluar: !mulaiMasuk)],
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _buka(WidgetTester tester, _Api api) async {
  await initializeDateFormatting('id_ID');
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      backendApiProvider.overrideWithValue(api),
      authSessionStoreProvider.overrideWithValue(_Sesi()),
    ],
    child: const MaterialApp(home: AbsensiPage()),
  ));
  await tester.pumpAndSettle();
}

Future<void> _tutup(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 1));
}

void main() {
  test('formatDurasi', () {
    expect(formatDurasi(0), '0 mnt');
    expect(formatDurasi(45), '45 mnt');
    expect(formatDurasi(120), '2 jam');
    expect(formatDurasi(135), '2 jam 15 mnt');
  });

  testWidgets('absen masuk mengirim outlet perangkat lalu tombol berubah jadi absen keluar', (tester) async {
    final api = _Api();
    await _buka(tester, api);
    expect(find.text('Belum absen masuk'), findsOneWidget);
    expect(find.text('Absen masuk'), findsOneWidget);
    expect(api.tzDikirim, DateTime.now().timeZoneOffset.inMinutes, reason: 'batas hari mengikuti zona perangkat');

    await tester.tap(find.byKey(const Key('absensi.tombol')));
    await tester.pumpAndSettle();
    expect(api.panggilan, containsAllInOrder(['saya', 'masuk', 'saya']));
    expect(api.outletDikirim, 'outlet-1');
    expect(find.textContaining('Sedang masuk sejak'), findsOneWidget);
    expect(find.text('Absen keluar'), findsOneWidget);

    await tester.tap(find.byKey(const Key('absensi.tombol')));
    await tester.pumpAndSettle();
    expect(api.panggilan.contains('keluar'), isTrue);
    expect(find.text('Belum absen masuk'), findsOneWidget);
    await _tutup(tester);
  });

  testWidgets('menampilkan rekap jam kerja dan riwayat', (tester) async {
    await _buka(tester, _Api());
    expect(find.byKey(const Key('absensi.rekap.Budi')), findsOneWidget);
    expect(find.text('2 jam 15 mnt'), findsWidgets);
    expect(find.byKey(const Key('absensi.item.a1')), findsOneWidget);
    await _tutup(tester);
  });

  testWidgets('sudah masuk dari awal: tombol langsung absen keluar', (tester) async {
    await _buka(tester, _Api(mulaiMasuk: true));
    expect(find.text('Absen keluar'), findsOneWidget);
    expect(find.text('berjalan'), findsOneWidget);
    await _tutup(tester);
  });

  testWidgets('paket tanpa fitur (403) menampilkan pesan jelas dan tombol coba lagi', (tester) async {
    await _buka(tester, _Api(statusGagal: 403));
    expect(find.textContaining('belum tersedia di paket'), findsOneWidget);
    expect(find.text('Coba lagi'), findsOneWidget);
    await _tutup(tester);
  });

  testWidgets('offline: pesan butuh internet', (tester) async {
    await _buka(tester, _Api(statusGagal: -1));
    expect(find.byKey(const Key('absensi.error')), findsOneWidget);
    await _tutup(tester);
  });
}
