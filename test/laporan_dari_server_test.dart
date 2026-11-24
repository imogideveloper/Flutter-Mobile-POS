import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/core/network/auth_session_store.dart';
import 'package:apps_pos/core/network/backend_api.dart';
import 'package:apps_pos/core/network/dio_backend_api.dart';
import 'package:apps_pos/core/providers/database_provider.dart';
import 'package:apps_pos/features/laporan/data/laporan_repository.dart' show PeriodeLaporan;
import 'package:apps_pos/features/laporan/domain/laporan_server.dart';
import 'package:apps_pos/features/laporan/presentation/providers/laporan_providers.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// HP yang baru masuk ulang tidak menyimpan transaksi lama: Laporan kosong padahal Riwayat (dari server) berisi
/// (ditemukan di HP 2026-11-24: Laporan 30 hari kosong, Riwayat 30 hari 19 transaksi).
class _Sesi extends AuthSessionStore {
  _Sesi() : super(const FlutterSecureStorage());

  @override
  Future<SesiBackend?> muat() async => const SesiBackend(
        accessToken: 't',
        refreshToken: 'r',
        tokoId: 'toko',
        outletId: 'outlet',
        penggunaId: 'u',
        perangkatId: 'p',
      );
}

class _Api implements BackendApi {
  _Api({this.gagal = false});

  final bool gagal;
  final List<String> path = [];

  @override
  Future<dynamic> getJson({required String accessToken, required String path, Map<String, dynamic>? query}) async {
    this.path.add(path);
    if (gagal) throw Exception('offline');
    if (path == '/laporan/penjualan') {
      return {
        'penjualan_bersih': '400000.00',
        'pajak_service': '29008.00',
        'total_penerimaan': '429008.00',
        'kas_diterima': '429008.00',
        'laba_kotor': '200000.00',
        'jumlah_transaksi': 19,
        'rata_rata': '21053.00',
        'jam_ramai': [
          {'jam': 13, 'total': '300000.00'},
          {'jam': 14, 'total': '100000.00'},
        ],
        'metode_bayar': [
          {'metode_bayar_id': 'metode-tunai-default', 'nama': 'Tunai', 'total': '429008.00', 'persen': '100.00'},
        ],
      };
    }
    if (path == '/laporan/produk-terlaris') {
      return [
        {'produk_id': 'p1', 'nama_produk': 'Kopi Susu', 'qty': '10.000', 'total': '180000.00'},
      ];
    }
    fail('jalur tak terduga: $path');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('laporanPerluDataServer: lokal kosong atau awal periode lebih lama dari transaksi lokal tertua', () {
    final hariIni = DateTime.now();
    final awalHari = DateTime(hariIni.year, hariIni.month, hariIni.day).toUtc().millisecondsSinceEpoch;
    final sore = DateTime(hariIni.year, hariIni.month, hariIni.day, 17).toUtc().millisecondsSinceEpoch;
    final bulanLalu = DateTime(hariIni.year, hariIni.month, hariIni.day).subtract(const Duration(days: 29)).toUtc().millisecondsSinceEpoch;

    expect(laporanPerluDataServer(awalMs: awalHari, palingAwalLokalMs: null), isTrue, reason: 'lokal kosong');
    expect(laporanPerluDataServer(awalMs: awalHari, palingAwalLokalMs: sore), isFalse, reason: 'hari ini tercakup lokal');
    expect(laporanPerluDataServer(awalMs: bulanLalu, palingAwalLokalMs: sore), isTrue, reason: '30 hari melewati data lokal');
  });

  test('ringkasanDariServer memetakan angka, jam ramai (digeser ke zona HP), metode bayar, dan produk terlaris', () {
    final hasil = ringkasanDariServer(
      penjualan: {
        'penjualan_bersih': '400000.00',
        'pajak_service': '29008.00',
        'total_penerimaan': '429008.00',
        'laba_kotor': '200000.00',
        'jumlah_transaksi': 19,
        'jam_ramai': [
          {'jam': 22, 'total': '1000.00'},
        ],
        'metode_bayar': [
          {'metode_bayar_id': 'm1', 'total': '400000.00', 'persen': '100.00'},
        ],
      },
      terlaris: [
        {'nama_produk': 'Kopi Susu', 'qty': '2.5', 'total': '45000.00'},
      ],
      sebelumnya: {'jumlah_transaksi': 0, 'penjualan_bersih': '0.00'},
      zona: const Duration(hours: 7),
    );
    expect(hasil.dariServer, isTrue);
    expect(hasil.penjualanBersih, 400000);
    expect(hasil.totalPenerimaan, 429008);
    expect(hasil.jumlahTransaksi, 19);
    expect(hasil.jamRamai.single.jam, 5, reason: '22 UTC + 7 jam = 05 keesokan harinya');
    expect(hasil.metodeBayar.single.metodeBayarId, 'm1');
    expect(hasil.produkTerlaris.single.namaProduk, 'Kopi Susu');
    expect(hasil.penjualanPeriodeSebelumnya, isNull, reason: 'periode sebelumnya tanpa transaksi');
  });

  ProviderContainer buat(AppDatabase db, _Api api) {
    final c = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWith((ref) => db),
      authSessionStoreProvider.overrideWithValue(_Sesi()),
      backendApiProvider.overrideWithValue(api),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  test('HP tanpa transaksi lama: Laporan 30 hari memakai rekap server', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final api = _Api();
    final c = buat(db, api);
    c.read(periodeLaporanProvider.notifier).state = PeriodeLaporan.tigaPuluhHari;

    final hasil = await c.read(ringkasanLaporanProvider.future);
    expect(hasil.dariServer, isTrue);
    expect(hasil.jumlahTransaksi, 19);
    expect(hasil.penjualanBersih, 400000);
    expect(hasil.produkTerlaris.single.namaProduk, 'Kopi Susu');
    expect(api.path, contains('/laporan/penjualan'));
  });

  test('server tidak terjangkau (offline): Laporan tetap tampil dari data lokal, tanpa galat', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final c = buat(db, _Api(gagal: true));
    c.read(periodeLaporanProvider.notifier).state = PeriodeLaporan.tigaPuluhHari;

    final hasil = await c.read(ringkasanLaporanProvider.future);
    expect(hasil.dariServer, isFalse);
    expect(hasil.jumlahTransaksi, 0);
  });
}
