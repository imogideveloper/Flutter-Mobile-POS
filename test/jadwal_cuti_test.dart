import 'package:apps_pos/core/network/auth_session_store.dart';
import 'package:apps_pos/core/network/backend_api.dart';
import 'package:apps_pos/core/network/backend_exception.dart';
import 'package:apps_pos/core/network/dio_backend_api.dart';
import 'package:apps_pos/core/providers/izin_provider.dart';
import 'package:apps_pos/features/jadwal/domain/jadwal_data.dart';
import 'package:apps_pos/features/jadwal/presentation/pages/jadwal_cuti_page.dart';
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
        outletId: 'outlet',
        penggunaId: 'saya',
        perangkatId: 'p',
      );
}

class _Api implements BackendApi {
  _Api({this.statusGagal});

  final int? statusGagal;
  final List<String> panggilan = [];
  Map<String, dynamic>? bodyAjuan;
  String? penggunaAtur;
  List<Map<String, dynamic>>? hariAtur;
  ({String id, bool setuju})? keputusan;
  String? dibatalkan;

  Map<String, dynamic> cuti(String id, String pengguna, String nama, String status) => {
        'id': id,
        'pengguna_id': pengguna,
        'pengguna_nama': nama,
        'jenis': 'cuti',
        'tanggal_mulai': '2026-12-01',
        'tanggal_selesai': '2026-12-03',
        'alasan': 'Acara keluarga',
        'status': status,
        'diputuskan_oleh': null,
        'diputuskan_pada': null,
        'catatan_keputusan': null,
      };

  @override
  Future<List<dynamic>> daftarJadwal({required String accessToken}) async {
    if (statusGagal != null) throw BackendException(message: 'x', statusCode: statusGagal == -1 ? null : statusGagal);
    return [
      {
        'pengguna_id': 'saya',
        'pengguna_nama': 'Owner Saya',
        'hari': [
          {'hari': 1, 'shift': 'pagi', 'jam_mulai': '07:00', 'jam_selesai': '15:00'},
          {'hari': 7, 'shift': 'libur', 'jam_mulai': null, 'jam_selesai': null},
        ],
      },
      {'pengguna_id': 'budi', 'pengguna_nama': 'Budi Kasir', 'hari': []},
    ];
  }

  @override
  Future<Map<String, dynamic>> aturJadwal({
    required String accessToken,
    required String penggunaId,
    required List<Map<String, dynamic>> hari,
  }) async {
    penggunaAtur = penggunaId;
    hariAtur = hari;
    return {'pengguna_id': penggunaId, 'pengguna_nama': 'x', 'hari': hari};
  }

  @override
  Future<Map<String, dynamic>> jadwalSaya({required String accessToken, required int tzMenit}) async => {
        'hari': [],
        'hari_ini': {
          'tanggal': '2026-11-14',
          'hari': 6,
          'shift': 'pagi',
          'jam_mulai': '07:00',
          'jam_selesai': '15:00',
          'cuti': null,
        },
      };

  @override
  Future<List<dynamic>> daftarCuti({required String accessToken, String? status}) async => [
        cuti('c-budi', 'budi', 'Budi Kasir', 'menunggu'),
        cuti('c-saya', 'saya', 'Owner Saya', 'menunggu'),
        cuti('c-ani', 'ani', 'Ani Kasir', 'disetujui'),
      ];

  @override
  Future<Map<String, dynamic>> ajukanCuti({required String accessToken, required Map<String, dynamic> body}) async {
    bodyAjuan = body;
    return cuti('baru', 'saya', 'Owner Saya', 'menunggu');
  }

  @override
  Future<Map<String, dynamic>> putuskanCuti({
    required String accessToken,
    required String cutiId,
    required bool setuju,
    String? catatan,
  }) async {
    keputusan = (id: cutiId, setuju: setuju);
    return cuti(cutiId, 'budi', 'Budi Kasir', setuju ? 'disetujui' : 'ditolak');
  }

  @override
  Future<Map<String, dynamic>> batalkanCuti({required String accessToken, required String cutiId}) async {
    dibatalkan = cutiId;
    return cuti(cutiId, 'saya', 'Owner Saya', 'dibatalkan');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _buka(WidgetTester tester, _Api api, {required Set<String> izin}) async {
  await initializeDateFormatting('id_ID');
  tester.view.physicalSize = const Size(900, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      backendApiProvider.overrideWithValue(api),
      authSessionStoreProvider.overrideWithValue(_Sesi()),
      izinSayaProvider.overrideWith((ref) async => izin),
    ],
    child: const MaterialApp(home: JadwalCutiPage()),
  ));
  await tester.pumpAndSettle();
}

Future<void> _tutup(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 1));
}

void main() {
  group('logika jadwal', () {
    test('label dan ringkasan', () {
      expect(labelShift('pagi'), 'Pagi');
      expect(labelShift(null), 'Belum diatur');
      expect(labelJenisCuti('sakit'), 'Sakit');
      expect(labelStatusCuti('menunggu'), 'Menunggu');
      const h = HariJadwal(hari: 1, shift: 'pagi', jamMulai: '07:00', jamSelesai: '15:00');
      expect(h.ringkas, 'Pagi 07:00-15:00');
      expect(const HariJadwal(hari: 7, shift: 'libur').ringkas, 'Libur');
    });

    test('JadwalKaryawan: shift per hari dan jumlah hari kerja', () {
      final k = JadwalKaryawan.dariJson({
        'pengguna_id': 'p',
        'pengguna_nama': 'Budi',
        'hari': [
          {'hari': 1, 'shift': 'pagi', 'jam_mulai': '07:00', 'jam_selesai': '15:00'},
          {'hari': 2, 'shift': 'libur'},
        ],
      });
      expect(k.shiftPada(1), 'pagi');
      expect(k.shiftPada(2), 'libur');
      expect(k.shiftPada(3), isNull);
      expect(k.jumlahHariKerja, 1);
    });

    test('JadwalHariIni.teks: cuti menang atas jadwal', () {
      expect(const JadwalHariIni(shift: 'pagi', jamMulai: '07:00', jamSelesai: '15:00').teks, 'Hari ini shift pagi 07:00-15:00');
      expect(const JadwalHariIni(shift: 'libur').teks, 'Hari ini libur');
      expect(const JadwalHariIni(shift: null).teks, 'Jadwal hari ini belum diatur');
      expect(const JadwalHariIni(shift: 'pagi', jamMulai: '07:00', jamSelesai: '15:00', cuti: 'sakit').teks, 'Sakit (disetujui)');
    });

    test('PengajuanCutiItem: jumlah hari dan menunggu', () {
      final c = PengajuanCutiItem.dariJson({
        'id': 'c', 'pengguna_id': 'p', 'pengguna_nama': 'Budi', 'jenis': 'cuti',
        'tanggal_mulai': '2026-12-01', 'tanggal_selesai': '2026-12-03', 'status': 'menunggu',
      });
      expect(c.jumlahHari, 3);
      expect(c.menunggu, isTrue);
    });

    test('badanJadwal hanya memuat hari yang valid dan terurut', () {
      expect(badanJadwal({3: 'siang', 1: 'pagi', 2: 'belum', 7: 'libur'}), [
        {'hari': 1, 'shift': 'pagi'},
        {'hari': 3, 'shift': 'siang'},
        {'hari': 7, 'shift': 'libur'},
      ]);
    });
  });

  testWidgets('pengelola: melihat semua karyawan, jadwal hari ini, dan menyimpan jadwal karyawan', (tester) async {
    final api = _Api();
    await _buka(tester, api, izin: {'laporan.lihat'});

    expect(find.text('Hari ini shift pagi 07:00-15:00'), findsOneWidget);
    expect(find.byKey(const Key('jadwal.karyawan.saya')), findsOneWidget);
    expect(find.byKey(const Key('jadwal.karyawan.budi')), findsOneWidget);
    expect(find.text('Sen Pagi'), findsOneWidget);
    expect(find.text('Min Libur'), findsOneWidget);

    await tester.tap(find.byKey(const Key('jadwal.karyawan.budi')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('jadwalForm.hari.1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Siang').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('jadwalForm.simpan')));
    await tester.pumpAndSettle();

    expect(api.penggunaAtur, 'budi');
    expect(api.hariAtur!.first, {'hari': 1, 'shift': 'siang'});
    expect(api.hariAtur!.length, 7, reason: 'semua hari dikirim, yang belum diatur menjadi libur');
    await _tutup(tester);
  });

  testWidgets('karyawan biasa tidak bisa mengatur jadwal (kartu tidak bisa diketuk)', (tester) async {
    await _buka(tester, _Api(), izin: {'transaksi.buat'});
    await tester.tap(find.byKey(const Key('jadwal.karyawan.budi')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('jadwalForm.simpan')), findsNothing);
    await _tutup(tester);
  });

  testWidgets('pengelola: setujui dan tolak pengajuan orang lain; milik sendiri hanya bisa dibatalkan', (tester) async {
    final api = _Api();
    await _buka(tester, api, izin: {'laporan.lihat'});
    await tester.tap(find.byKey(const Key('jadwal.tabCuti')));
    await tester.pumpAndSettle();

    expect(find.text('2 pengajuan menunggu keputusan'), findsOneWidget);
    expect(find.byKey(const Key('jadwal.setuju.c-budi')), findsOneWidget);
    expect(find.byKey(const Key('jadwal.tolak.c-budi')), findsOneWidget);
    expect(find.byKey(const Key('jadwal.setuju.c-saya')), findsNothing, reason: 'tidak memutuskan pengajuan sendiri');
    expect(find.byKey(const Key('jadwal.batalkan.c-saya')), findsOneWidget);
    expect(find.byKey(const Key('jadwal.setuju.c-ani')), findsNothing, reason: 'sudah diputuskan');

    await tester.tap(find.byKey(const Key('jadwal.setuju.c-budi')));
    await tester.pumpAndSettle();
    expect(api.keputusan, (id: 'c-budi', setuju: true));

    await tester.tap(find.byKey(const Key('jadwal.batalkan.c-saya')));
    await tester.pumpAndSettle();
    expect(api.dibatalkan, 'c-saya');
    await _tutup(tester);
  });

  testWidgets('karyawan biasa: tidak ada tombol putuskan, mengajukan cuti mengirim body yang benar', (tester) async {
    final api = _Api();
    await _buka(tester, api, izin: {'transaksi.buat'});
    await tester.tap(find.byKey(const Key('jadwal.tabCuti')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('jadwal.setuju.c-budi')), findsNothing);
    expect(find.byKey(const Key('jadwal.menunggu')), findsNothing);

    await tester.tap(find.byKey(const Key('jadwal.ajukan')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('cutiForm.alasan')), 'Menikah');
    await tester.tap(find.byKey(const Key('cutiForm.kirim')));
    await tester.pumpAndSettle();

    final b = api.bodyAjuan!;
    expect(b['jenis'], 'cuti');
    expect(b['alasan'], 'Menikah');
    expect(b['tanggal_mulai'], matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
    expect((b['tanggal_mulai'] as String).compareTo(b['tanggal_selesai'] as String) <= 0, isTrue);
    await _tutup(tester);
  });

  testWidgets('paket terkunci (403) dan offline menampilkan pesan jelas', (tester) async {
    await _buka(tester, _Api(statusGagal: 403), izin: {});
    expect(find.textContaining('belum tersedia di paket'), findsOneWidget);
    await _tutup(tester);

    await _buka(tester, _Api(statusGagal: -1), izin: {});
    expect(find.byKey(const Key('jadwal.error')), findsOneWidget);
    expect(find.textContaining('Butuh internet'), findsOneWidget);
    await _tutup(tester);
  });
}
