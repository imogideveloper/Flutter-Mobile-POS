import 'package:apps_pos/core/auth/pin_hash.dart';
import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/core/database/seed.dart';
import 'package:apps_pos/core/network/auth_session_store.dart';
import 'package:apps_pos/core/network/connectivity_provider.dart';
import 'package:apps_pos/core/providers/database_provider.dart';
import 'package:apps_pos/core/providers/session_provider.dart';
import 'package:apps_pos/core/providers/toko_profile_provider.dart';
import 'package:apps_pos/features/transaksi/data/local/tables/transaksi_table.dart';
import 'package:apps_pos/main.dart';
import 'package:drift/drift.dart' hide isNull;
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

class _LoginOwner extends PenggunaSessionNotifier {
  @override
  String? build() => 'owner-ani';
}

/// Ditemukan di HP 2026-11-23 (uji peran Kasir): Riwayat menampilkan SEMUA transaksi hari ini milik kasir lain dan
/// "Total penerimaan" toko, padahal Kasir tidak punya izin laporan.lihat.
void main() {
  Future<AppDatabase> siapkanDb() async {
    final db = AppDatabase(NativeDatabase.memory());
    await seedRoleDanOwner(db);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    Future<void> pengguna(String id, String roleId, String nama) => db.into(db.pengguna).insert(
          PenggunaCompanion.insert(
            id: id,
            tokoId: 'toko-default',
            roleId: roleId,
            nama: nama,
            pinHash: Value(hashPin('123456')),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await pengguna('owner-ani', 'role-owner', 'Ani Owner');
    await pengguna('kasir-budi', 'role-kasir', 'Budi Kasir');
    Future<void> trx(String id, String struk, String penggunaId, int total) => db.into(db.transaksi).insert(
          TransaksiCompanion.insert(
            id: id,
            tokoId: 'toko-default',
            outletId: 'outlet-default',
            penggunaId: penggunaId,
            nomorStruk: struk,
            tanggal: now,
            status: TransaksiStatus.selesai,
            total: Value(total),
            totalBayar: Value(total),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await trx('t-budi', 'STR-BUDI', 'kasir-budi', 17000);
    await trx('t-ani', 'STR-ANI', 'owner-ani', 23000);
    return db;
  }

  Future<void> buka(WidgetTester tester, AppDatabase db, PenggunaSessionNotifier Function() login) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWith((ref) => db),
        currentPenggunaIdProvider.overrideWith(login),
        authSessionStoreProvider.overrideWithValue(_StoreNull()),
        tokoProfileProvider.overrideWith((ref) async => null),
        isOnlineProvider.overrideWith((ref) => Stream.value(true)),
      ],
      child: const AppsPosApp(),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Riwayat').first);
    await tester.pumpAndSettle();
  }

  testWidgets('Kasir hanya melihat transaksi miliknya dan totalnya, bukan milik kasir lain', (tester) async {
    final db = await siapkanDb();
    addTearDown(db.close);
    await buka(tester, db, _LoginKasir.new);

    expect(find.text('#STR-BUDI'), findsOneWidget);
    expect(find.text('#STR-ANI'), findsNothing, reason: 'transaksi kasir lain tidak boleh terlihat');
    expect(find.text('Rp17.000'), findsWidgets, reason: 'total penerimaan hanya milik sendiri');
    expect(find.text('Rp40.000'), findsNothing, reason: 'total penerimaan seluruh toko tidak boleh terlihat Kasir');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('Owner (punya laporan.lihat) tetap melihat semua transaksi dan total toko', (tester) async {
    final db = await siapkanDb();
    addTearDown(db.close);
    await buka(tester, db, _LoginOwner.new);

    expect(find.text('#STR-BUDI'), findsOneWidget);
    expect(find.text('#STR-ANI'), findsOneWidget);
    expect(find.text('Rp40.000'), findsWidgets);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
