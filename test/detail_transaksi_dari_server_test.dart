import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/core/network/auth_session_store.dart';
import 'package:apps_pos/core/network/backend_api.dart';
import 'package:apps_pos/core/network/dio_backend_api.dart';
import 'package:apps_pos/core/providers/database_provider.dart';
import 'package:apps_pos/features/transaksi/data/local/tables/transaksi_table.dart' show TransaksiStatus;
import 'package:apps_pos/features/transaksi/presentation/providers/transaksi_providers.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// Membuka transaksi dari Riwayat (yang diambil dari server) menampilkan "Gagal memuat transaksi" bila transaksi itu
/// tidak ada di database HP (ditemukan di HP 2026-11-24 setelah masuk ulang).
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
  @override
  Future<Map<String, dynamic>> ambilDetailTransaksi({required String accessToken, required String transaksiId}) async => {
        'id': transaksiId,
        'nomor_struk': 'STR-1',
        'nomor_antrean': null,
        'tanggal': '2026-11-23T16:54:00Z',
        'status': 'selesai',
        'subtotal': '16500.00',
        'total_diskon': '0.00',
        'total_pajak': '825.00',
        'total': '17325.00',
        'total_bayar': '20000.00',
        'kembalian': '2675.00',
        'alasan_void': null,
        'snapshot_struk': {
          'data': {
            'items': [
              {'namaProduk': 'Roti Bakar', 'qty': 1.0, 'hargaSatuan': 16500, 'subtotal': 16500, 'modifiers': <String>[]},
            ],
            'rincianPajak': [
              {'nama': 'PB1', 'persen': 5.0, 'jumlah': 825, 'termasukHarga': false},
            ],
          },
        },
      };

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('transaksi yang tidak ada di HP dibuka dari server (lihat dan cetak ulang saja)', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final c = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWith((ref) => db),
      authSessionStoreProvider.overrideWithValue(_Sesi()),
      backendApiProvider.overrideWithValue(_Api()),
    ]);
    addTearDown(c.dispose);

    final d = await c.read(detailTransaksiProvider('trx-server').future);
    expect(d.dariServer, isTrue);
    expect(d.nomorStruk, 'STR-1');
    expect(d.status, TransaksiStatus.selesai);
    expect(d.total, 17325);
    expect(d.totalBayar, 20000);
    expect(d.kembalian, 2675);
    expect(d.items.single.namaProduk, 'Roti Bakar');
    expect(d.rincianPajak.single.jumlah, 825);
    expect(d.snapshotStruk, isNotNull, reason: 'cetak ulang memakai snapshot dari server');
  });
}
