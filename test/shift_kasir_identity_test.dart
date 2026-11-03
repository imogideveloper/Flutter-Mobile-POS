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

class _FakeAuthSessionStoreNull extends AuthSessionStore {
  _FakeAuthSessionStoreNull() : super(const FlutterSecureStorage());

  @override
  Future<SesiBackend?> muat() async => null;
}

/// Tahap 5b - sebelum identitas karyawan disatukan dgn server, kartu
/// shift aktif (lihat shift_page.dart) tidak pernah menampilkan nama
/// kasir sama sekali (selalu diam2 "pasti Owner"). Test ini mengunci
/// perilaku baru: kartu HARUS menampilkan nama kasir YANG SEBENARNYA
/// membuka shift (shift.penggunaId), bukan Owner default.
class _LoginSebagaiKasirBudi extends PenggunaSessionNotifier {
  @override
  String? build() => 'kasir-budi';
}

void main() {
  testWidgets('kartu shift aktif menampilkan nama kasir yang sebenarnya membuka shift (bukan Owner)',
      (tester) async {
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

    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWith((ref) => db),
        currentPenggunaIdProvider.overrideWith(_LoginSebagaiKasirBudi.new),
        authSessionStoreProvider.overrideWithValue(_FakeAuthSessionStoreNull()),
        tokoProfileProvider.overrideWith((ref) async => null),
        isOnlineProvider.overrideWith((ref) => Stream.value(true)),
      ],
      child: const AppsPosApp(),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Produk'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shift'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Buka Shift'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('bukaShiftForm.modalAwal')), '100000');
    await tester.tap(find.text('Mulai shift'));
    await tester.pumpAndSettle();

    expect(find.text('Shift sedang berjalan'), findsOneWidget);
    expect(find.text('Budi Kasir'), findsOneWidget);
    expect(find.text('Owner (default)'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
