import 'package:apps_pos/core/auth/pin_hash.dart';
import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/core/database/seed.dart';
import 'package:apps_pos/core/network/auth_session_store.dart';
import 'package:apps_pos/core/network/connectivity_provider.dart';
import 'package:apps_pos/core/providers/database_provider.dart';
import 'package:apps_pos/core/providers/session_provider.dart';
import 'package:apps_pos/core/providers/toko_profile_provider.dart';
import 'package:apps_pos/main.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _StoreNull extends AuthSessionStore {
  _StoreNull() : super(const FlutterSecureStorage());

  @override
  Future<SesiBackend?> muat() async => null;
}

class _LoginKasir extends PenggunaSessionNotifier {
  @override
  String? build() => 'kasir-budi';
}

void main() {
  testWidgets('kasir (tanpa tab Produk) tetap bisa keluar/ganti kasir lewat Lainnya', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await seedRoleDanOwner(db);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await db.into(db.pengguna).insert(PenggunaCompanion.insert(
          id: 'kasir-budi',
          tokoId: 'toko-default',
          roleId: 'role-kasir',
          nama: 'Budi Kasir',
          pinHash: Value(hashPin('123456')),
          createdAt: now,
          updatedAt: now,
        ));

    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWith((ref) => db),
        currentPenggunaIdProvider.overrideWith(_LoginKasir.new),
        authSessionStoreProvider.overrideWithValue(_StoreNull()),
        tokoProfileProvider.overrideWith((ref) async => null),
        isOnlineProvider.overrideWith((ref) => Stream.value(true)),
      ],
      child: const AppsPosApp(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Produk'), findsNothing);
    await tester.tap(find.text('Lainnya'));
    await tester.pumpAndSettle();
    expect(find.text('Keluar / ganti kasir'), findsOneWidget);
    expect(find.text('Budi Kasir'), findsWidgets);
    await tester.tap(find.text('Keluar / ganti kasir'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    // Sesi berakhir: bar tab tidak ada lagi, kembali ke gerbang login.
    expect(find.text('Lainnya'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
