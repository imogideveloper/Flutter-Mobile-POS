import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/core/network/auth_session_store.dart';
import 'package:apps_pos/core/network/backend_api.dart';
import 'package:apps_pos/core/network/connectivity_provider.dart';
import 'package:apps_pos/core/network/dio_backend_api.dart' show backendApiProvider;
import 'package:apps_pos/core/providers/database_provider.dart';
import 'package:apps_pos/core/providers/session_provider.dart';
import 'package:apps_pos/core/providers/toko_profile_provider.dart';
import 'package:apps_pos/features/transaksi/data/local/tables/transaksi_table.dart';
import 'package:apps_pos/main.dart';
import 'package:drift/drift.dart';
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
        tokoId: 'toko-1',
        outletId: 'outlet-default',
        penggunaId: 'pengguna-1',
        perangkatId: 'perangkat-1',
      );
}

/// Server balas list KOSONG (simulasi: transaksi lokal belum sempat
/// ter-push ke server - wajar, sync offline-first tidak instan).
class _FakeBackendApiKosong implements BackendApi {
  @override
  Future<Map<String, dynamic>> ambilTransaksi({
    required String accessToken,
    required String outletId,
    required String dariTanggal,
    required String sampaiTanggal,
    int limit = 200,
    int offset = 0,
  }) async => {'items': <Map<String, dynamic>>[]};

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// Regresi utk bug nyata yang dilaporkan pengguna: "transaksi yang udah
/// dijalankan gak muncul" di Riwayat. Akar masalah: `_remoteItems ??
/// lokalTerfilter` MENGGANTIKAN total data lokal begitu fetch server
/// sukses, walau hasilnya kosong/tidak lengkap (krn transaksi itu belum
/// sempat tersinkron ke server). Sekarang digabung (lihat
/// _gabungkanLokalDanRemote di riwayat_list_page.dart) - data lokal yang
/// SUNGGUHAN ADA tidak boleh hilang hanya krn server belum tahu soal itu.
void main() {
  testWidgets(
      'transaksi lokal tetap tampil di Riwayat walau server balas kosong utk rentang yang sama',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final sekarang = DateTime.now().toUtc();
    await db.into(db.transaksi).insert(TransaksiCompanion.insert(
          id: 't-lokal-belum-sync',
          tokoId: 'toko-default',
          outletId: 'outlet-default',
          penggunaId: 'pengguna-default',
          nomorStruk: 'OUT1-LOKAL',
          tanggal: sekarang.millisecondsSinceEpoch,
          status: TransaksiStatus.selesai,
          total: const Value(15000),
          totalBayar: const Value(15000),
          createdAt: sekarang.millisecondsSinceEpoch,
          updatedAt: sekarang.millisecondsSinceEpoch,
        ));

    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWith((ref) => db),
        currentPenggunaIdProvider.overrideWith(_LangsungLogin.new),
        authSessionStoreProvider.overrideWithValue(_FakeAuthSessionStoreTerisi()),
        backendApiProvider.overrideWithValue(_FakeBackendApiKosong()),
        tokoProfileProvider.overrideWith((ref) async => null),
        isOnlineProvider.overrideWith((ref) => Stream.value(true)),
      ],
      child: const AppsPosApp(),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Riwayat').first);
    await tester.pumpAndSettle();

    // Pindah ke preset "30 hari" - memicu _perluDataServer (dari = 30 hari
    // lalu, jelas sebelum tanggal transaksi satu2nya yang ada) sehingga
    // _cobaAmbilDariServer() benar2 jalan dan _remoteItems terisi (kosong).
    await tester.tap(find.byKey(const Key('riwayatForm.filterTanggal')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('30 hari'));
    await tester.pumpAndSettle();
    // Beri jeda utk addPostFrameCallback._cobaAmbilDariServer selesai.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    // Transaksi lokal WAJIB tetap tampil - sebelum fix ini, baris ini
    // gagal krn _remoteItems (list kosong dari server) menimpa total data
    // lokal.
    expect(find.text('#OUT1-LOKAL'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
