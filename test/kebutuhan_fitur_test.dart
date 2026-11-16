import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/core/widgets/fitur_terkunci.dart';
import 'package:apps_pos/features/fitur/presentation/providers/feature_gate_provider.dart';
import 'package:apps_pos/main.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

void main() {
  group('FeatureGate.relevan', () {
    FeatureGate gate(Map<String, String> k) =>
        FeatureGate(paket: 'Pro', kodeAktif: const {}, batas: const {}, kebutuhan: k);

    test('hanya na yang dianggap tidak relevan', () {
      final g = gate({'a': 'inti', 'b': 'opsional', 'c': 'na'});
      expect(g.relevan('a'), isTrue);
      expect(g.relevan('b'), isTrue);
      expect(g.relevan('c'), isFalse);
    });

    test('kode tanpa klasifikasi dan cache kosong dianggap relevan', () {
      expect(gate({'a': 'na'}).relevan('tidak-ada'), isTrue);
      expect(gate(const {}).relevan('apa-saja'), isTrue);
    });
  });

  test('DAO: simpanKebutuhan mengganti total klasifikasi dan terpisah per toko', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await db.fiturDao.simpanKebutuhan('t1', {'pay_later': 'na', 'diskon': 'inti'});
    await db.fiturDao.simpanKebutuhan('t2', {'kasbon': 'opsional'});
    expect(await db.fiturDao.semuaKebutuhan('t1'), {'pay_later': 'na', 'diskon': 'inti'});

    await db.fiturDao.simpanKebutuhan('t1', {'diskon': 'opsional'});
    expect(await db.fiturDao.semuaKebutuhan('t1'), {'diskon': 'opsional'}, reason: 'diganti total, bukan digabung');
    expect(await db.fiturDao.semuaKebutuhan('t2'), {'kasbon': 'opsional'});

    await db.fiturDao.simpanKebutuhan('t1', const {});
    expect(await db.fiturDao.semuaKebutuhan('t1'), isEmpty);
  });

  testWidgets('FiturTerkunci: tidak relevan disembunyikan (bukan dikunci), selain itu tampil', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.fiturDao.simpanStatusFitur(
      tokoId: 'toko-default',
      paket: 'Pro',
      kodeFiturAktif: const ['a', 'b', 'c'],
      batasPerKode: const {},
      updatedAt: 0,
    );
    await db.fiturDao.simpanKebutuhan('toko-default', {'a': 'inti', 'b': 'opsional', 'c': 'na', 'd': 'na'});

    await tester.pumpWidget(ProviderScope(
      overrides: overridesSudahLogin(db),
      child: const MaterialApp(
        home: Scaffold(
          body: Column(children: [
            FiturTerkunci(kode: 'a', child: Text('tombol-a')),
            FiturTerkunci(kode: 'b', child: Text('tombol-b')),
            FiturTerkunci(kode: 'c', child: Text('tombol-c')),
            FiturTerkunci(kode: 'd', child: Text('tombol-d')), // tidak relevan DAN terkunci (tidak ada di kodeAktif)
            FiturTerkunci(kode: 'e', child: Text('tombol-e')), // tanpa klasifikasi, terkunci
          ]),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('tombol-a'), findsOneWidget);
    expect(find.text('tombol-b'), findsOneWidget);
    expect(find.text('tombol-c'), findsNothing);
    expect(find.text('tombol-d'), findsNothing);
    expect(find.byKey(const Key('fiturTerkunci.d')), findsNothing, reason: 'disembunyikan, bukan ikon gembok');
    expect(find.byKey(const Key('fiturTerkunci.e')), findsOneWidget, reason: 'tanpa klasifikasi tetap perilaku lama (terkunci)');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });

  Future<void> bukaLainnya(WidgetTester tester, AppDatabase db) async {
    tester.view.physicalSize = const Size(900, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(overrides: overridesSudahLogin(db), child: const AppsPosApp()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lainnya'));
    await tester.pumpAndSettle();
  }

  testWidgets('menu Order belum dibayar: tampil untuk jenis usaha yang relevan, hilang bila tidak relevan', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await seedMetodeBayarUjiCoba(db);
    await db.fiturDao.simpanStatusFitur(
      tokoId: 'toko-default',
      paket: 'Pro',
      kodeFiturAktif: const ['pay_later'],
      batasPerKode: const {},
      updatedAt: 0,
    );

    // Relevan (mis. kafe/restoran): menu tampil.
    await db.fiturDao.simpanKebutuhan('toko-default', {'pay_later': 'inti'});
    await bukaLainnya(tester, db);
    expect(find.text('Order belum dibayar'), findsOneWidget);

    // Tidak relevan (mis. toko minuman): menu hilang setelah sync membawa klasifikasi baru.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
    await db.fiturDao.simpanKebutuhan('toko-default', {'pay_later': 'na'});
    await bukaLainnya(tester, db);
    expect(find.text('Order belum dibayar'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
