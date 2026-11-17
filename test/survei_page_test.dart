import 'package:apps_pos/core/network/auth_session_store.dart';
import 'package:apps_pos/core/network/backend_api.dart';
import 'package:apps_pos/core/network/dio_backend_api.dart';
import 'package:apps_pos/features/survei/presentation/pages/survei_page.dart';
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

final _survei = {
  'id': 's1',
  'judul': 'Kepuasan',
  'tampil_di': 'struk',
  'aktif': true,
  'pertanyaan': [
    {'id': 'q1', 'teks': 'Seberapa puas?', 'tipe': 'rating', 'opsi': null, 'wajib': true, 'urutan': 0},
    {'id': 'q2', 'teks': 'Saran?', 'tipe': 'teks', 'opsi': null, 'wajib': false, 'urutan': 1},
  ],
};

class _Api implements BackendApi {
  final List<(String, Map<String, dynamic>?)> kiriman = [];

  @override
  Future<dynamic> getJson({required String accessToken, required String path, Map<String, dynamic>? query}) async {
    if (path == '/survei') return [_survei];
    if (path == '/survei/s1/hasil') {
      return {
        'survei_id': 's1',
        'judul': 'Kepuasan',
        'jumlah_responden': 3,
        'pertanyaan': [
          {
            'pertanyaan_id': 'q1',
            'teks': 'Seberapa puas?',
            'tipe': 'rating',
            'jumlah_jawaban': 3,
            'rata_rata': 4.0,
            'sebaran': {'1': 0, '2': 0, '3': 1, '4': 1, '5': 1},
            'komentar': <String>[],
          },
        ],
      };
    }
    throw StateError('path tak terduga $path');
  }

  @override
  Future<dynamic> postJson({required String accessToken, required String path, Map<String, dynamic>? body}) async {
    kiriman.add((path, body));
    return {'id': 'j1'};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _buka(WidgetTester tester, _Api api, Widget home) async {
  tester.view.physicalSize = const Size(900, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      backendApiProvider.overrideWithValue(api),
      authSessionStoreProvider.overrideWithValue(_Sesi()),
    ],
    child: MaterialApp(home: home),
  ));
  await tester.pumpAndSettle();
}

Future<void> _tutup(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 1));
}

void main() {
  test('validasiSurveiBaru menolak judul kosong, tanpa pertanyaan, dan pilihan kurang dari 2 opsi', () {
    expect(validasiSurveiBaru('', [PertanyaanSurveiBaru(teks: 'a')]), isNotNull);
    expect(validasiSurveiBaru('J', []), isNotNull);
    expect(validasiSurveiBaru('J', [PertanyaanSurveiBaru(teks: '')]), isNotNull);
    expect(validasiSurveiBaru('J', [PertanyaanSurveiBaru(teks: 'a', tipe: 'pilihan', opsi: 'satu')]), isNotNull);
    expect(validasiSurveiBaru('J', [PertanyaanSurveiBaru(teks: 'a', tipe: 'pilihan', opsi: 'satu, dua')]), isNull);
    expect(PertanyaanSurveiBaru(teks: ' a ', tipe: 'pilihan', opsi: 'x, ,y').toJson(), {
      'teks': 'a',
      'tipe': 'pilihan',
      'wajib': false,
      'opsi': ['x', 'y'],
    });
  });

  testWidgets('daftar survei menampilkan judul dan jumlah pertanyaan', (tester) async {
    await _buka(tester, _Api(), const SurveiPage());
    expect(find.text('Kepuasan'), findsOneWidget);
    expect(find.text('2 pertanyaan'), findsOneWidget);
    expect(find.byKey(const Key('survei.buat')), findsOneWidget);
    await _tutup(tester);
  });

  testWidgets('mengisi jawaban: pertanyaan wajib dicek, lalu rating dan komentar dikirim', (tester) async {
    final api = _Api();
    await _buka(tester, api, IsiSurveiPage(survei: _survei));

    await tester.tap(find.byKey(const Key('survei.kirim')));
    await tester.pump();
    expect(api.kiriman, isEmpty, reason: 'rating wajib belum diisi');

    await tester.tap(find.byKey(const Key('survei.rating.q1.4')));
    await tester.enterText(find.byKey(const Key('survei.teks.q2')), 'Enak');
    await tester.tap(find.byKey(const Key('survei.kirim')));
    await tester.pumpAndSettle();

    expect(api.kiriman.single.$1, '/survei/s1/jawaban');
    expect(api.kiriman.single.$2!['jawaban'], [
      {'pertanyaan_id': 'q1', 'nilai_angka': 4},
      {'pertanyaan_id': 'q2', 'nilai_teks': 'Enak'},
    ]);
    await _tutup(tester);
  });

  testWidgets('hasil menampilkan responden dan rata-rata', (tester) async {
    await _buka(tester, _Api(), const HasilSurveiPage(surveiId: 's1', judul: 'Kepuasan'));
    expect(find.text('3 responden'), findsOneWidget);
    expect(find.text('Rata-rata 4.0 dari 5'), findsOneWidget);
    await _tutup(tester);
  });
}
