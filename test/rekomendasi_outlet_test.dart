import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/core/network/auth_session_store.dart';
import 'package:apps_pos/core/network/backend_api.dart';
import 'package:apps_pos/core/network/connectivity_provider.dart';
import 'package:apps_pos/core/network/dio_backend_api.dart';
import 'package:apps_pos/core/providers/database_provider.dart';
import 'package:apps_pos/core/providers/toko_profile_provider.dart';
import 'package:apps_pos/features/lainnya/domain/rekomendasi_outlet.dart';
import 'package:apps_pos/features/lainnya/presentation/pages/pengaturan_outlet_struk_page.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _Sesi extends AuthSessionStore {
  _Sesi() : super(const FlutterSecureStorage());

  @override
  Future<SesiBackend?> muat() async => const SesiBackend(
        accessToken: 'token',
        refreshToken: 'refresh',
        tokoId: 'toko-1',
        outletId: 'outlet-1',
        penggunaId: 'pengguna-1',
        perangkatId: 'perangkat-1',
      );
}

/// Server berisi pengaturan yang sudah diubah jauh dari rekomendasi.
class _Api implements BackendApi {
  Map<String, dynamic>? bodyDikirim;

  @override
  Future<Map<String, dynamic>> ambilPengaturanOutlet({required String accessToken, required String outletId}) async => {
        'header_struk': 'Jl. Contoh 1',
        'footer_struk': 'Sampai jumpa',
        'lebar_kertas_mm': 80,
        'tampil_logo': false,
        'gaya_logo': 'unggah',
        'struk_ringkas': false,
        'pakai_nomor_antrean': false,
        'antrean_awalan': 'Z',
        'antrean_mulai': 500,
        'estimasi_menit': 30,
        'batas_margin': 10,
        'izinkan_stok_minus': false,
        'pembulatan': 500,
      };

  @override
  Future<Map<String, dynamic>> ubahPengaturanOutlet({
    required String accessToken,
    required String outletId,
    required Map<String, dynamic> body,
  }) async {
    bodyDikirim = body;
    return {...body, 'outlet_id': outletId};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  group('rekomendasiOutlet', () {
    test('kafe, roti, minuman, dan food court: struk ringkas dan antrean menyala', () {
      for (final j in [JenisUsaha.kafe, JenisUsaha.roti, JenisUsaha.minuman, JenisUsaha.kios]) {
        final r = rekomendasiOutlet(j);
        expect(r.strukRingkas, isTrue, reason: j.name);
        expect(r.pakaiNomorAntrean, isTrue, reason: j.name);
      }
    });

    test('restoran, katering, bahan segar: struk lengkap tanpa antrean', () {
      for (final j in [JenisUsaha.restoran, JenisUsaha.katering, JenisUsaha.bahanSegar]) {
        final r = rekomendasiOutlet(j);
        expect(r.strukRingkas, isFalse, reason: j.name);
        expect(r.pakaiNomorAntrean, isFalse, reason: j.name);
      }
    });

    test('nilai umum mengikuti panduan', () {
      final r = rekomendasiOutlet(JenisUsaha.kafe);
      expect(r.footerStruk, 'Terima kasih, selamat menikmati!');
      expect(r.batasMargin, 50);
      expect(r.lebarKertasMm, 58);
      expect(r.pembulatan, 0);
    });
  });

  testWidgets('Kembalikan ke rekomendasi mengisi form dan baru tersimpan setelah Simpan', (tester) async {
    tester.view.physicalSize = const Size(900, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.fiturDao.simpanStatusFitur(
      tokoId: 'toko-default',
      paket: 'Bisnis',
      kodeFiturAktif: const ['logo_struk', 'struk_ringkas', 'nomor_antrean'],
      batasPerKode: const {},
      updatedAt: 0,
    );
    final api = _Api();

    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWith((r) => db),
        authSessionStoreProvider.overrideWithValue(_Sesi()),
        backendApiProvider.overrideWithValue(api),
        isOnlineProvider.overrideWith((r) => Stream.value(true)),
        tokoProfileProvider.overrideWith(
          (r) async => const TokoProfile(namaToko: 'Kopi Senja', jenisUsaha: JenisUsaha.kafe, namaPemilik: 'Rina'),
        ),
      ],
      child: const MaterialApp(home: PengaturanOutletStrukPage()),
    ));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('pengaturanOutletForm.rekomendasi')));
    await tester.tap(find.byKey(const Key('pengaturanOutletForm.rekomendasi')));
    await tester.pumpAndSettle();
    expect(find.text('Kembalikan ke rekomendasi?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('pengaturanOutletForm.rekomendasiYa')));
    await tester.pumpAndSettle();
    expect(api.bodyDikirim, isNull, reason: 'belum disimpan sebelum menekan Simpan');

    await tester.ensureVisible(find.byKey(const Key('pengaturanOutletForm.simpan')));
    await tester.tap(find.byKey(const Key('pengaturanOutletForm.simpan')));
    await tester.pumpAndSettle();

    final b = api.bodyDikirim!;
    expect(b['header_struk'], isNull);
    expect(b['footer_struk'], 'Terima kasih, selamat menikmati!');
    expect(b['lebar_kertas_mm'], 58);
    expect(b['struk_ringkas'], true);
    expect(b['pakai_nomor_antrean'], true);
    expect(b['antrean_awalan'], 'A');
    expect(b['antrean_mulai'], 1);
    expect(b['estimasi_menit'], 0);
    expect(b['batas_margin'], 50);
    expect(b['pembulatan'], 0);
    expect(b['izinkan_stok_minus'], true);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
