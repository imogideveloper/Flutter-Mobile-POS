import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/core/providers/database_provider.dart';
import 'package:apps_pos/core/providers/session_provider.dart';
import 'package:apps_pos/core/widgets/fitur_terkunci.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('FiturTerkunci menampilkan ikon gembok kalau fitur belum terbuka', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWith((ref) => db)],
        child: const MaterialApp(
          home: Scaffold(
            body: FiturTerkunci(kode: 'resep', child: Text('Pakai resep bahan baku')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('fiturTerkunci.resep')), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    expect(find.text('Pakai resep bahan baku'), findsOneWidget); // child tetap dirender, cuma redup
  });

  testWidgets('FiturTerkunci tidak menampilkan gembok kalau fitur sudah terbuka', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final container = ProviderContainer(overrides: [appDatabaseProvider.overrideWith((ref) => db)]);
    addTearDown(container.dispose);
    final tokoId = container.read(currentTokoIdProvider);
    await db.fiturDao.simpanStatusFitur(
      tokoId: tokoId,
      paket: 'Bisnis',
      kodeFiturAktif: const ['resep'],
      batasPerKode: const {},
      updatedAt: 0,
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: FiturTerkunci(kode: 'resep', child: Text('Pakai resep bahan baku')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('fiturTerkunci.resep')), findsNothing);
    expect(find.byIcon(Icons.lock_outline), findsNothing);
    expect(find.text('Pakai resep bahan baku'), findsOneWidget);
  });

  testWidgets('menekan area terkunci membuka bottom sheet "Tersedia di paket"', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWith((ref) => db)],
        child: const MaterialApp(
          home: Scaffold(
            body: FiturTerkunci(kode: 'resep', child: Text('Pakai resep bahan baku')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('fiturTerkunci.resep')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Tersedia di paket'), findsNothing); // paketMinimal lokal null
    expect(find.textContaining('belum tersedia di paket toko kamu'), findsOneWidget);
  });
}
