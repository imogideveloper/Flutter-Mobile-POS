import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/features/pelanggan/presentation/pages/pelanggan_list_page.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

void main() {
  testWidgets('daftar pelanggan menandai yang berulang tahun hari ini saja', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final sekarang = DateTime.now();
    final besok = sekarang.add(const Duration(days: 1));

    Future<void> pelanggan(String id, String nama, int? lahir) => db.pelangganDao.upsertPelanggan(
          PelangganCompanion.insert(
            id: id,
            tokoId: 'toko-default',
            nama: nama,
            tanggalLahir: Value(lahir),
            createdAt: 1,
            updatedAt: 1,
          ),
        );

    // Tahun 2000 (kabisat) supaya 29 Februari tidak mengubah hasil.
    await pelanggan('a', 'Sari Hari Ini', 2000 * 10000 + sekarang.month * 100 + sekarang.day);
    await pelanggan('b', 'Budi Besok', 2000 * 10000 + besok.month * 100 + besok.day);
    await pelanggan('c', 'Ani Tanpa Lahir', null);

    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: overridesSudahLogin(db),
      child: const MaterialApp(home: PelangganListPage()),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('pelangganList.ulangTahun.a')), findsOneWidget);
    expect(find.byKey(const Key('pelangganList.ulangTahun.b')), findsNothing);
    expect(find.byKey(const Key('pelangganList.ulangTahun.c')), findsNothing);
    expect(find.text('Ulang tahun hari ini'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
