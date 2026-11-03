import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/core/network/auth_session_store.dart';
import 'package:apps_pos/core/network/backend_api.dart';
import 'package:apps_pos/core/network/connectivity_provider.dart';
import 'package:apps_pos/core/network/dio_backend_api.dart';
import 'package:apps_pos/core/providers/database_provider.dart';
import 'package:apps_pos/core/providers/session_provider.dart';
import 'package:apps_pos/core/providers/toko_profile_provider.dart';
import 'package:apps_pos/main.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _LangsungLogin extends PenggunaSessionNotifier {
  @override
  String? build() => 'pengguna-default';
}

class _FakeAuthSessionStoreTerisi extends AuthSessionStore {
  _FakeAuthSessionStoreTerisi() : super(const FlutterSecureStorage());

  @override
  Future<SesiBackend?> muat() async => const SesiBackend(
        accessToken: 'token',
        refreshToken: 'refresh',
        tokoId: 'toko-default',
        outletId: 'outlet-default',
        penggunaId: 'pengguna-default',
        perangkatId: 'perangkat-1',
      );
}

/// Tahap 5b lanjutan - produk sekarang ONLINE-DIRECT (sama pola dgn
/// Karyawan/Promo/Pajak) - /sync/push ternyata tidak pernah bisa membawa
/// produk sama sekali, jadi produk lokal lama permanen hilang kalau HP
/// di-uninstall sebelum sempat (kalaupun bisa) disinkron.
class _FakeBackendApiProduk implements BackendApi {
  @override
  Future<dynamic> postJson({
    required String accessToken,
    required String path,
    Map<String, dynamic>? body,
  }) async {
    return {
      'id': 'produk-baru',
      'toko_id': 'toko-default',
      'kategori_id': null,
      'satuan_id': null,
      'sku': body!['sku'],
      'barcode': body['barcode'],
      'nama': body['nama'],
      'tipe': body['tipe'],
      'lacak_stok': body['lacak_stok'],
      'hpp': body['hpp'],
      'harga_jual': body['harga_jual'],
      'aktif': body['aktif'],
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  testWidgets('list produk -> tambah produk -> muncul kembali di list',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWith((ref) => db),
        currentPenggunaIdProvider.overrideWith(_LangsungLogin.new),
        authSessionStoreProvider.overrideWithValue(_FakeAuthSessionStoreTerisi()),
        backendApiProvider.overrideWithValue(_FakeBackendApiProduk()),
        tokoProfileProvider.overrideWith((ref) async => null),
        isOnlineProvider.overrideWith((ref) => Stream.value(true)),
      ],
      child: const AppsPosApp(),
    ));
    await tester.pumpAndSettle();

    // App mendarat di tab Kasir (default) - pindah ke tab Produk dulu.
    await tester.tap(find.text('Produk'));
    await tester.pumpAndSettle();

    expect(find.text('Belum ada produk'), findsOneWidget);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(find.text('Tambah produk'), findsOneWidget);

    const nama = 'Produk Uji Kopi';
    await tester.enterText(find.byKey(const Key('produkForm.nama')), nama);
    await tester.enterText(find.byKey(const Key('produkForm.hargaJual')), '12345');

    // Form produk cukup panjang (beberapa card) - scroll dulu supaya
    // tombol Simpan di bawah benar-benar bisa dites tap().
    for (var i = 0; i < 5; i++) {
      await tester.drag(find.byKey(const Key('produkForm.scrollView')), const Offset(0, -300));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simpan produk'));
    await tester.pumpAndSettle();

    expect(find.text('Tambah produk'), findsNothing);
    expect(find.text(nama), findsOneWidget);
    expect(find.text('Rp12.345'), findsOneWidget);

    // Lepas widget tree secara eksplisit supaya timer cleanup internal
    // drift (dipicu saat stream query di-cancel) sempat selesai sebelum
    // binding test memverifikasi tidak ada pending timer.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
