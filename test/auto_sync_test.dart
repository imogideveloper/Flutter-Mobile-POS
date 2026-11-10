import 'dart:async';

import 'package:apps_pos/core/network/auto_sync.dart';
import 'package:apps_pos/core/network/connectivity_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Sync otomatis (TASK-111, BUG-004): pemicu, jeda minimum, backoff saat gagal, dan tidak pernah
/// dua sync bersamaan.
void main() {
  late DateTime waktu;
  late int jumlahJalan;
  late int jumlahSelesai;
  Future<void> Function() isiJalankan = () async {};
  bool siapNilai = true;

  AutoSync buat({Duration jeda = const Duration(seconds: 30)}) => AutoSync(
        jalankan: () => isiJalankan(),
        siap: () async => siapNilai,
        setelahSelesai: () => jumlahSelesai++,
        jedaMinimum: jeda,
        sekarang: () => waktu,
      );

  setUp(() {
    waktu = DateTime(2026, 11, 11, 9);
    jumlahJalan = 0;
    jumlahSelesai = 0;
    siapNilai = true;
    isiJalankan = () async => jumlahJalan++;
  });

  group('AutoSync', () {
    test('menjalankan sync dan memberi tahu setelah sukses', () async {
      final a = buat();
      expect(await a.picu(), isTrue);
      expect((jumlahJalan, jumlahSelesai), (1, 1));
    });

    test('pemicu berulang dalam jeda minimum diabaikan; setelah jeda jalan lagi; paksa melewati jeda', () async {
      final a = buat();
      await a.picu();
      waktu = waktu.add(const Duration(seconds: 10));
      expect(await a.picu(), isFalse);
      expect(jumlahJalan, 1);

      expect(await a.picu(paksa: true), isTrue, reason: 'mis. setelah pembayaran selesai');
      expect(jumlahJalan, 2);

      waktu = waktu.add(const Duration(seconds: 31));
      expect(await a.picu(), isTrue);
      expect(jumlahJalan, 3);
    });

    test('tidak pernah dua sync bersamaan, walau dipaksa', () async {
      final selesai = Completer<void>();
      isiJalankan = () async {
        jumlahJalan++;
        await selesai.future;
      };
      final a = buat();
      final pertama = a.picu();
      await Future<void>.delayed(Duration.zero);
      expect(a.sedangBerjalan, isTrue);
      expect(await a.picu(paksa: true), isFalse);
      selesai.complete();
      expect(await pertama, isTrue);
      expect(jumlahJalan, 1);
    });

    test('gagal tidak melempar, jeda berlipat sampai batas 15 menit, dan sukses mengembalikan jeda normal', () async {
      var gagal = true;
      isiJalankan = () async {
        jumlahJalan++;
        if (gagal) throw Exception('server mati');
      };
      final a = buat();

      expect(await a.picu(), isFalse);
      expect(a.gagalBerturut, 1);
      expect(a.jedaSaatIni, const Duration(seconds: 60));

      for (var i = 0; i < 12; i++) {
        waktu = waktu.add(const Duration(hours: 1));
        await a.picu();
      }
      expect(a.jedaSaatIni, const Duration(minutes: 15), reason: 'tidak melebihi batas maksimum');
      expect(jumlahSelesai, 0);

      // Dalam jeda yang melebar, pemicu biasa ditahan.
      final sebelum = jumlahJalan;
      waktu = waktu.add(const Duration(minutes: 5));
      expect(await a.picu(), isFalse);
      expect(jumlahJalan, sebelum);

      gagal = false;
      waktu = waktu.add(const Duration(minutes: 20));
      expect(await a.picu(), isTrue);
      expect(a.gagalBerturut, 0);
      expect(a.jedaSaatIni, const Duration(seconds: 30));
      expect(jumlahSelesai, 1);
    });

    test('perangkat belum dipasangkan: tidak menjalankan apa pun dan tidak dihitung gagal', () async {
      siapNilai = false;
      final a = buat();
      expect(await a.picu(), isFalse);
      expect(jumlahJalan, 0);
      expect(a.gagalBerturut, 0);
    });
  });

  group('AutoSyncHost', () {
    testWidgets('memicu saat dibuka, berkala, saat aplikasi kembali aktif, dan saat koneksi pulih', (tester) async {
      var dipicu = 0;
      final fake = _FakeAutoSync(() => dipicu++);
      final online = StreamController<bool>();
      addTearDown(online.close);

      await tester.pumpWidget(ProviderScope(
        overrides: [
          autoSyncProvider.overrideWithValue(fake),
          isOnlineProvider.overrideWith((ref) => online.stream),
        ],
        child: const MaterialApp(home: AutoSyncHost(interval: Duration(minutes: 5), child: Text('isi'))),
      ));
      await tester.pump();
      expect(dipicu, 1, reason: 'sync pertama setelah aplikasi tampil');

      await tester.pump(const Duration(minutes: 5));
      expect(dipicu, 2, reason: 'berkala');

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(dipicu, 3, reason: 'kembali ke aplikasi');

      online.add(false);
      await tester.pump();
      expect(dipicu, 3, reason: 'offline tidak memicu');
      online.add(true);
      await tester.pump();
      expect(dipicu, 4, reason: 'koneksi pulih');

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(minutes: 10));
      expect(dipicu, 4, reason: 'timer berhenti saat host dilepas');
    });
  });
}

class _FakeAutoSync extends AutoSync {
  _FakeAutoSync(this.onPicu) : super(jalankan: () async {}, siap: () async => true);

  final void Function() onPicu;

  @override
  Future<bool> picu({bool paksa = false}) async {
    onPicu();
    return true;
  }
}
