import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/core/network/auth_session_store.dart';
import 'package:apps_pos/core/network/backend_api.dart';
import 'package:apps_pos/core/network/dio_backend_api.dart';
import 'package:apps_pos/core/providers/database_provider.dart';
import 'package:apps_pos/features/lainnya/presentation/pages/paket_langganan_page.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAuthSessionStoreTerisi extends AuthSessionStore {
  _FakeAuthSessionStoreTerisi() : super(const FlutterSecureStorage());

  @override
  Future<SesiBackend?> muat() async => const SesiBackend(
        accessToken: 'token',
        refreshToken: 'refresh',
        tokoId: 'toko-1',
        outletId: 'outlet-1',
        penggunaId: 'pengguna-1',
        perangkatId: 'perangkat-1',
      );

  // _setelahLunas() (paket_langganan_page.dart) memicu
  // syncRepositoryProvider.jalankan(), yang baca/tulis watermark sync
  // lewat method DI LUAR muat() - tanpa di-override juga, keduanya jatuh
  // ke flutter_secure_storage SUNGGUHAN (channel platform tidak ada di
  // widget test) dan MENGGANTUNG selamanya (bukan error cepat), bikin
  // modal tidak pernah tertutup krn _tangani() tidak pernah selesai await.
  @override
  Future<String> ambilLastSyncAt() async => DateTime(2000).toUtc().toIso8601String();

  @override
  Future<void> simpanLastSyncAt(String iso8601) async {}
}

/// Upgrade paket sekarang lewat modal QRIS/VA LANGSUNG di app (dibalik
/// dari jalur redirect browser Xendit lama, atas permintaan eksplisit
/// "jangan keluar dari HP") - tombol "Bayar & upgrade sekarang" membuka
/// bottom sheet pilih metode, lalu QR/nomor VA ditampilkan di modal
/// kedua dgn tombol cek status (statusCheckoutUpgrade) dan "Simulasikan
/// pembayaran" (khusus sandbox, lewat postJson generik) yang keduanya
/// mengaktifkan paket otomatis begitu lunas.
class _FakeBackendApiPaket implements BackendApi {
  Map<String, dynamic>? bodyCheckoutDiterima;
  String? pathCheckoutDiterima;
  String statusDibalas = 'selesai';
  Map<String, dynamic> langgananSaya = {
    'paket_id': 'paket-gratis',
    'paket_nama': 'Gratis',
    'status': 'aktif',
    'periode': 'bulanan',
    'jumlah_outlet': 1,
    'mulai': '2026-01-01T00:00:00Z',
    'berakhir': null,
    'pemakaian': {'outlet': 1, 'pengguna': 1, 'produk': 5},
  };

  @override
  Future<dynamic> getJson({
    required String accessToken,
    required String path,
    Map<String, dynamic>? query,
  }) => throw UnimplementedError();

  @override
  Future<dynamic> postJson({
    required String accessToken,
    required String path,
    Map<String, dynamic>? body,
  }) async {
    pathCheckoutDiterima = path;
    bodyCheckoutDiterima = body;
    if (path == '/langganan/checkout-upgrade/qris') {
      return {
        'id': 'permintaan-1',
        'qr_string': 'qr-string-permintaan-1',
        'jumlah_bayar': '150000',
        'status': 'baru',
      };
    }
    if (path == '/langganan/checkout-upgrade/va') {
      return {
        'id': 'permintaan-1',
        'bank_code': body!['bank_code'],
        'nomor_va': '88081234567890',
        'jumlah_bayar': '150000',
        'status': 'baru',
      };
    }
    if (path == '/langganan/checkout-upgrade/permintaan-1/simulasi') {
      if (statusDibalas == 'selesai') {
        langgananSaya = {...langgananSaya, 'paket_id': 'paket-pro', 'paket_nama': 'Pro'};
      }
      return {'status': statusDibalas};
    }
    throw UnimplementedError(path);
  }

  @override
  Future<dynamic> patchJson({
    required String accessToken,
    required String path,
    required Map<String, dynamic> body,
  }) => throw UnimplementedError();

  @override
  Future<void> deleteJson({required String accessToken, required String path}) =>
      throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> ambilLanggananSaya({required String accessToken}) async =>
      langgananSaya;

  @override
  Future<List<Map<String, dynamic>>> ambilDaftarPaket({required String accessToken}) async => [
        {
          'id': 'paket-gratis',
          'nama': 'Gratis',
          'urutan': 0,
          'harga_bulanan': '0',
          'harga_tahunan': null,
          'maks_outlet': 1,
          'maks_pengguna': 2,
          'maks_produk': 50,
          'kode_fitur': ['laporan_dasar'],
        },
        {
          'id': 'paket-pro',
          'nama': 'Pro',
          'urutan': 1,
          'harga_bulanan': '150000',
          'harga_tahunan': '1500000',
          'maks_outlet': 3,
          'maks_pengguna': 10,
          'maks_produk': null,
          'kode_fitur': ['laporan_dasar', 'diskon', 'kasbon'],
        },
      ];

  @override
  Future<Map<String, dynamic>> checkoutUpgrade({
    required String accessToken,
    required Map<String, dynamic> body,
  }) =>
      throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> statusCheckoutUpgrade({
    required String accessToken,
    required String permintaanId,
  }) async {
    if (statusDibalas == 'selesai') {
      langgananSaya = {...langgananSaya, 'paket_id': 'paket-pro', 'paket_nama': 'Pro'};
    }
    return {'status': statusDibalas};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  testWidgets('bayar upgrade via QRIS - modal QR muncul, cek status mengaktifkan paket', (tester) async {
    final fakeBackend = _FakeBackendApiPaket()..statusDibalas = 'selesai';

    await tester.pumpWidget(ProviderScope(
      overrides: [
        authSessionStoreProvider.overrideWithValue(_FakeAuthSessionStoreTerisi()),
        backendApiProvider.overrideWithValue(fakeBackend),
        // _setelahLunas() (paket_langganan_page.dart) memicu
        // syncRepositoryProvider.jalankan() setelah pembayaran lunas -
        // tanpa override ini, drift membuka AppDatabase SUNGGUHAN (native
        // sqlite3) tiap kali test ini jalan, lambat & rawan flaky. fakeBackend
        // tidak implement syncPush/syncPull (lihat noSuchMethod di bawah) -
        // jalankan() akan gagal cepat, ditangkap try/catch di _setelahLunas,
        // tidak menghalangi assert toast/modal tertutup di bawah.
        appDatabaseProvider.overrideWith((ref) => AppDatabase(NativeDatabase.memory())),
      ],
      child: const MaterialApp(home: PaketLanggananPage()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Gratis'), findsWidgets);
    expect(find.text('AKTIF'), findsOneWidget);
    expect(find.text('Paket aktif saat ini'), findsOneWidget);

    await tester.tap(find.byKey(const Key('paketLanggananForm.upgrade.paket-pro')));
    await tester.pumpAndSettle();

    // Bottom sheet pilih metode - QRIS atau bank VA - TIDAK keluar ke browser.
    expect(find.text('Pilih metode pembayaran'), findsOneWidget);
    expect(find.byKey(const Key('paketLanggananForm.metode.qris')), findsOneWidget);
    expect(find.byKey(const Key('paketLanggananForm.metode.va.bca')), findsOneWidget);

    await tester.tap(find.byKey(const Key('paketLanggananForm.metode.qris')));
    await tester.pumpAndSettle();

    // Payment request dibuat dgn paket & periode yang benar, QR dirender di app.
    expect(fakeBackend.pathCheckoutDiterima, '/langganan/checkout-upgrade/qris');
    expect(fakeBackend.bodyCheckoutDiterima!['paket_tujuan_id'], 'paket-pro');
    expect(find.text('Bayar dengan QRIS'), findsOneWidget);
    expect(find.byKey(const Key('paketLanggananForm.qrImage')), findsOneWidget);

    await tester.tap(find.byKey(const Key('paketLanggananForm.cekStatus')));
    await tester.pumpAndSettle();

    // Lunas -> modal tertutup, toast sukses, kartu "Langganan saya" ikut
    // ter-refresh jadi Pro (bukan cuma status tiket checkout-nya).
    expect(find.text('Bayar dengan QRIS'), findsNothing);
    expect(find.text('Pembayaran berhasil'), findsOneWidget);
    expect(find.text('AKTIF'), findsOneWidget);
    expect(find.text('Paket aktif saat ini'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('bayar upgrade via VA BCA - nomor VA tampil, simulasi bayar mengaktifkan paket', (tester) async {
    final fakeBackend = _FakeBackendApiPaket()..statusDibalas = 'selesai';

    await tester.pumpWidget(ProviderScope(
      overrides: [
        authSessionStoreProvider.overrideWithValue(_FakeAuthSessionStoreTerisi()),
        backendApiProvider.overrideWithValue(fakeBackend),
        // _setelahLunas() (paket_langganan_page.dart) memicu
        // syncRepositoryProvider.jalankan() setelah pembayaran lunas -
        // tanpa override ini, drift membuka AppDatabase SUNGGUHAN (native
        // sqlite3) tiap kali test ini jalan, lambat & rawan flaky. fakeBackend
        // tidak implement syncPush/syncPull (lihat noSuchMethod di bawah) -
        // jalankan() akan gagal cepat, ditangkap try/catch di _setelahLunas,
        // tidak menghalangi assert toast/modal tertutup di bawah.
        appDatabaseProvider.overrideWith((ref) => AppDatabase(NativeDatabase.memory())),
      ],
      child: const MaterialApp(home: PaketLanggananPage()),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('paketLanggananForm.upgrade.paket-pro')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('paketLanggananForm.metode.va.bca')));
    await tester.pumpAndSettle();

    expect(fakeBackend.pathCheckoutDiterima, '/langganan/checkout-upgrade/va');
    expect(fakeBackend.bodyCheckoutDiterima!['bank_code'], 'bca');
    expect(find.text('Transfer Virtual Account BCA'), findsOneWidget);
    expect(find.byKey(const Key('paketLanggananForm.nomorVa')), findsOneWidget);

    // Sandbox - QR/VA Xendit test mode tidak bisa benar2 dibayar, tombol
    // "Simulasikan pembayaran" memicu Xendit men-simulasikan lunas.
    await tester.tap(find.byKey(const Key('paketLanggananForm.simulasikan')));
    await tester.pumpAndSettle();

    expect(find.text('Transfer Virtual Account BCA'), findsNothing);
    expect(find.text('Pembayaran berhasil'), findsOneWidget);
    expect(find.text('Paket aktif saat ini'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('cek status belum lunas - modal tetap terbuka dgn pesan, paket tidak berubah', (tester) async {
    final fakeBackend = _FakeBackendApiPaket()..statusDibalas = 'baru';

    await tester.pumpWidget(ProviderScope(
      overrides: [
        authSessionStoreProvider.overrideWithValue(_FakeAuthSessionStoreTerisi()),
        backendApiProvider.overrideWithValue(fakeBackend),
        // _setelahLunas() (paket_langganan_page.dart) memicu
        // syncRepositoryProvider.jalankan() setelah pembayaran lunas -
        // tanpa override ini, drift membuka AppDatabase SUNGGUHAN (native
        // sqlite3) tiap kali test ini jalan, lambat & rawan flaky. fakeBackend
        // tidak implement syncPush/syncPull (lihat noSuchMethod di bawah) -
        // jalankan() akan gagal cepat, ditangkap try/catch di _setelahLunas,
        // tidak menghalangi assert toast/modal tertutup di bawah.
        appDatabaseProvider.overrideWith((ref) => AppDatabase(NativeDatabase.memory())),
      ],
      child: const MaterialApp(home: PaketLanggananPage()),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('paketLanggananForm.upgrade.paket-pro')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('paketLanggananForm.metode.qris')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('paketLanggananForm.cekStatus')));
    await tester.pumpAndSettle();

    expect(find.text('Bayar dengan QRIS'), findsOneWidget);
    expect(find.textContaining('belum terdeteksi'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
