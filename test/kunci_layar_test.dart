import 'package:apps_pos/core/auth/kunci_layar.dart';
import 'package:apps_pos/core/providers/session_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _MenitTetap extends KunciLayarMenitNotifier {
  _MenitTetap(this.menit);
  final int menit;

  @override
  Future<int> build() async => menit;
}

class _Login extends PenggunaSessionNotifier {
  _Login(this.id);
  final String? id;

  @override
  String? build() => id;
}

Future<int Function()> _pasang(WidgetTester tester, {required int menit, String? pengguna = 'u1'}) async {
  var jumlahKunci = 0;
  await tester.pumpWidget(ProviderScope(
    overrides: [
      kunciLayarMenitProvider.overrideWith(() => _MenitTetap(menit)),
      currentPenggunaIdProvider.overrideWith(() => _Login(pengguna)),
    ],
    child: MaterialApp(
      home: KunciLayarHost(
        kunci: () => jumlahKunci++,
        child: const Scaffold(body: Center(child: Text('isi'))),
      ),
    ),
  ));
  await tester.pump();
  await tester.tapAt(const Offset(10, 10)); // sentuhan pertama menjadwalkan timer
  await tester.pump();
  return () => jumlahKunci;
}

void main() {
  testWidgets('mengunci setelah jeda tanpa sentuhan', (tester) async {
    final kunci = await _pasang(tester, menit: 2);
    await tester.pump(const Duration(minutes: 1, seconds: 59));
    expect(kunci(), 0);
    await tester.pump(const Duration(seconds: 2));
    expect(kunci(), 1);
  });

  testWidgets('sentuhan memulai ulang hitungan', (tester) async {
    final kunci = await _pasang(tester, menit: 2);
    await tester.pump(const Duration(minutes: 1, seconds: 30));
    await tester.tapAt(const Offset(10, 10));
    await tester.pump(const Duration(minutes: 1, seconds: 30));
    expect(kunci(), 0, reason: 'hitungan mulai lagi dari sentuhan terakhir');
    await tester.pump(const Duration(seconds: 40));
    expect(kunci(), 1);
  });

  testWidgets('jeda 0 (mati) tidak pernah mengunci', (tester) async {
    final kunci = await _pasang(tester, menit: 0);
    await tester.pump(const Duration(hours: 3));
    expect(kunci(), 0);
  });

  testWidgets('belum ada pengguna masuk: tidak ada yang dikunci', (tester) async {
    final kunci = await _pasang(tester, menit: 2, pengguna: null);
    await tester.pump(const Duration(minutes: 10));
    expect(kunci(), 0);
  });

  testWidgets('kembali dari latar belakang setelah melewati jeda langsung mengunci', (tester) async {
    final kunci = await _pasang(tester, menit: 2);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(minutes: 3));
    // Timer sudah berjalan di FakeAsync; pastikan hanya terkunci sekali walau resume menyusul.
    final sebelum = kunci();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(kunci() - sebelum, 0);
    expect(sebelum, 1);
  });
}
