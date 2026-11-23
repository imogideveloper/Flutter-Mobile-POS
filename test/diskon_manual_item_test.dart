import 'package:apps_pos/core/auth/pin_hash.dart';
import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/core/database/seed.dart';
import 'package:apps_pos/core/network/auth_session_store.dart';
import 'package:apps_pos/core/network/connectivity_provider.dart';
import 'package:apps_pos/core/providers/database_provider.dart';
import 'package:apps_pos/core/providers/session_provider.dart';
import 'package:apps_pos/core/providers/toko_profile_provider.dart';
import 'package:apps_pos/features/produk/data/local/tables/produk_table.dart';
import 'package:apps_pos/features/stok/data/local/tables/mutasi_stok_table.dart';
import 'package:apps_pos/features/transaksi/domain/item_keranjang.dart';
import 'package:apps_pos/main.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

class _StoreNull extends AuthSessionStore {
  _StoreNull() : super(const FlutterSecureStorage());

  @override
  Future<SesiBackend?> muat() async => null;
}

class _LoginOwner extends PenggunaSessionNotifier {
  @override
  String? build() => 'owner-ani';
}

class _LoginKasir extends PenggunaSessionNotifier {
  @override
  String? build() => 'kasir-budi';
}

Future<AppDatabase> _siapkanDb() async {
  final db = AppDatabase(NativeDatabase.memory());
  await seedRoleDanOwner(db);
  final now = DateTime.now().toUtc().millisecondsSinceEpoch;
  Future<void> pengguna(String id, String roleId, String nama, String pin) => db.into(db.pengguna).insert(
        PenggunaCompanion.insert(
          id: id,
          tokoId: 'toko-default',
          roleId: roleId,
          nama: nama,
          pinHash: Value(hashPin(pin)),
          createdAt: now,
          updatedAt: now,
        ),
      );
  await pengguna('owner-ani', 'role-owner', 'Ani Owner', '111111');
  await pengguna('kasir-budi', 'role-kasir', 'Budi Kasir', '222222');
  await db.produkDao.upsertProduk(ProdukCompanion.insert(
    id: 'p1',
    tokoId: 'toko-default',
    nama: 'Kopi Hitam',
    tipe: ProdukTipe.barang,
    hargaJual: const Value(50000),
    createdAt: 0,
    updatedAt: 0,
  ));
  await db.stokDao.catatMutasi(
    tokoId: 'toko-default',
    outletId: 'outlet-default',
    produkId: 'p1',
    jenis: MutasiJenis.stokAwal,
    qty: 10,
  );
  await seedMetodeBayarUjiCoba(db);
  await db.fiturDao.simpanStatusFitur(
    tokoId: 'toko-default',
    paket: 'Gratis',
    kodeFiturAktif: const ['diskon'],
    batasPerKode: const {},
    updatedAt: 0,
  );
  return db;
}

Future<void> _bukaApp(WidgetTester tester, AppDatabase db, PenggunaSessionNotifier Function() login) async {
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
  await tester.tap(find.text('Buka Shift'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('bukaShiftForm.modalAwal')), '0');
  await tester.tap(find.text('Mulai shift'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Kopi Hitam'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Lihat keranjang'));
  await tester.pumpAndSettle();
}

Future<void> _tutup(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 1));
}

void main() {
  group('ItemKeranjang', () {
    const dasar = ItemKeranjang(produkId: 'p', namaProduk: 'Kopi', hargaSatuan: 20000, qty: 2, lacakStok: false);

    test('tanpa diskon: nol', () {
      expect(dasar.adaDiskonManual, isFalse);
      expect(dasar.diskonManual, 0);
    });

    test('diskon persen mengikuti qty', () {
      final d = dasar.denganDiskon(persen: 10);
      expect(d.diskonManual, 4000); // 10% dari 40.000
      expect(d.copyWith(qty: 5).diskonManual, 10000, reason: '10% dari 100.000 setelah qty berubah');
    });

    test('diskon nominal tetap dan tidak pernah melebihi nilai baris', () {
      expect(dasar.denganDiskon(nominal: 5000).diskonManual, 5000);
      expect(dasar.denganDiskon(nominal: 999999).diskonManual, 40000);
      expect(dasar.denganDiskon(nominal: -5).diskonManual, 0);
    });

    test('mengganti bentuk diskon menimpa yang lama, dan tanpa argumen menghapusnya', () {
      final persen = dasar.denganDiskon(persen: 10);
      expect(persen.denganDiskon(nominal: 3000).diskonPersen, isNull);
      expect(persen.denganDiskon().adaDiskonManual, isFalse);
    });
  });

  testWidgets('Owner memasang diskon 10%: total turun, tersimpan dengan penyetujunya', (tester) async {
    final db = await _siapkanDb();
    addTearDown(db.close);
    await _bukaApp(tester, db, _LoginOwner.new);

    await tester.tap(find.byKey(const Key('keranjang.diskonItem.p1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('diskonItem.sheet')), findsOneWidget);

    await tester.tap(find.byKey(const Key('diskonItem.cepat.10')));
    await tester.pumpAndSettle();

    // Owner punya izin transaksi.diskon: langsung terpasang, tanpa PIN.
    expect(find.textContaining('Perlu approval'), findsNothing);
    expect(find.byKey(const Key('keranjang.diskon.p1')), findsOneWidget);
    expect(find.text('Diskon 10%: -Rp5.000'), findsOneWidget);
    expect(find.text('Rp45.000'), findsWidgets);

    await tester.tap(find.text('Bayar Rp45.000'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('bayarForm.uangDiterima')), '45000');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('bayarForm.selesaikan')));
    await tester.pumpAndSettle();
    expect(find.text('Pembayaran berhasil'), findsOneWidget);
    // Struk di layar menjelaskan selisih baris (50.000) ke Subtotal (45.000), sama dengan struk cetak (AT6).
    expect(find.text('  Diskon'), findsOneWidget);
    expect(find.text('-Rp5.000'), findsOneWidget);

    final transaksi = (await db.select(db.transaksi).get()).single;
    expect(transaksi.subtotal, 45000);
    expect(transaksi.total, 45000);
    expect(transaksi.diskonManualDisetujuiOleh, 'owner-ani');
    final item = (await db.select(db.itemTransaksi).get()).single;
    expect(item.diskon, 5000);
    expect(item.subtotal, 45000);

    await _tutup(tester);
  });

  testWidgets('Kasir tanpa izin diminta PIN: PIN salah ditolak, PIN owner diterima', (tester) async {
    final db = await _siapkanDb();
    addTearDown(db.close);
    await _bukaApp(tester, db, _LoginKasir.new);

    await tester.tap(find.byKey(const Key('keranjang.diskonItem.p1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('diskonItem.cepat.20')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Perlu approval'), findsOneWidget);

    // PIN salah -> tidak disetujui, diskon tidak terpasang.
    await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), '999999');
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Konfirmasi')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('keranjang.diskon.p1')), findsNothing);

    // PIN owner -> disetujui atas nama owner.
    await tester.tap(find.byKey(const Key('diskonItem.cepat.20')));
    await tester.pumpAndSettle();
    await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), '111111');
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Konfirmasi')));
    await tester.pumpAndSettle();
    expect(find.text('Diskon 20%: -Rp10.000'), findsOneWidget);

    await tester.tap(find.text('Bayar Rp40.000'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('bayarForm.uangDiterima')), '40000');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('bayarForm.selesaikan')));
    await tester.pumpAndSettle();
    final transaksi = (await db.select(db.transaksi).get()).single;
    expect(transaksi.diskonManualDisetujuiOleh, 'owner-ani', reason: 'yang menyetujui owner, bukan kasir yang menjual');
    expect(transaksi.penggunaId, 'kasir-budi');

    await _tutup(tester);
  });
}
