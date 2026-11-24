import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/network/auth_session_store.dart';
import '../../../../core/network/dio_backend_api.dart';
import '../../../../core/providers/database_provider.dart';
import '../../../../core/providers/session_provider.dart';
import '../../../pelanggan/presentation/providers/pelanggan_providers.dart';
import '../../../produk/presentation/providers/produk_providers.dart';
import '../../../stok/presentation/providers/stok_providers.dart';
import '../../data/local/metode_bayar_dao.dart';
import '../../data/local/transaksi_dao.dart';
import '../../data/transaksi_repository.dart';
import '../../domain/detail_transaksi.dart';
import '../../domain/ringkasan_transaksi.dart';

final transaksiDaoProvider = Provider<TransaksiDao>((ref) {
  return ref.watch(appDatabaseProvider).transaksiDao;
});

final metodeBayarDaoProvider = Provider<MetodeBayarDao>((ref) {
  return ref.watch(appDatabaseProvider).metodeBayarDao;
});

/// Metode bayar aktif toko ini, dari drift lokal (hasil pull-sync) - bukan
/// placeholder lagi (F3.A) seperti metodeBayarTunaiIdProvider/
/// metodeBayarQrisIdProvider lama di session_provider.dart yang id-nya
/// tidak pernah match baris backend sungguhan manapun.
final metodeBayarAktifProvider = StreamProvider<List<MetodeBayarRow>>((ref) {
  return ref.watch(metodeBayarDaoProvider).watchMetodeBayarAktif();
});

/// Peta id metode bayar -> nama (termasuk yang nonaktif, karena transaksi lama masih
/// merujuknya) untuk label di riwayat, detail, dan laporan.
final namaMetodeBayarProvider = StreamProvider<Map<String, String>>((ref) {
  return ref.watch(metodeBayarDaoProvider).watchSemuaMetodeBayar().map(
        (rows) => {for (final r in rows) r.id: r.nama},
      );
});

final transaksiRepositoryProvider = Provider<TransaksiRepository>((ref) {
  return TransaksiRepository(
    ref.watch(transaksiDaoProvider),
    ref.watch(stokDaoProvider),
    ref.watch(produkDaoProvider),
  );
});

final transaksiShiftProvider =
    StreamProvider.family<List<TransaksiRow>, String>((ref, shiftId) {
  return ref.watch(transaksiDaoProvider).watchTransaksiShift(shiftId);
});

final riwayatTransaksiProvider = StreamProvider<List<RingkasanTransaksi>>((ref) {
  final outletId = ref.watch(currentOutletIdProvider);
  return ref.watch(transaksiRepositoryProvider).watchRiwayat(outletId);
});

final detailTransaksiProvider =
    FutureProvider.family<DetailTransaksi, String>((ref, transaksiId) async {
  final namaPelanggan = await ref.watch(namaPelangganUntukTransaksiProvider(transaksiId).future);
  try {
    return await ref.watch(transaksiRepositoryProvider).detailTransaksi(
          transaksiId,
          namaPelanggan: namaPelanggan,
        );
  } on StateError {
    // Transaksi tidak ada di database HP ini (dibuat di HP lain atau sebelum masuk ulang): ambil dari server.
    final sesi = await ref.read(authSessionStoreProvider).muat();
    if (sesi == null) rethrow;
    final resp = await ref.read(backendApiProvider).ambilDetailTransaksi(
          accessToken: sesi.accessToken,
          transaksiId: transaksiId,
        );
    return detailTransaksiDariServer(resp, namaPelanggan: namaPelanggan);
  }
});

/// Dipisah dari [detailTransaksiProvider] supaya tidak perlu import modul
/// Pelanggan langsung ke TransaksiRepository (lihat komentar di
/// detailTransaksi) - lookup nama dilakukan di layer provider ini saja.
final namaPelangganUntukTransaksiProvider =
    FutureProvider.family<String?, String>((ref, transaksiId) async {
  // Transaksi yang tidak ada di HP ini (diambil dari server) tidak punya nama pelanggan lokal.
  final row = await ref.watch(transaksiDaoProvider).transaksiById(transaksiId).then<TransaksiRow?>((r) => r, onError: (_) => null);
  if (row == null) return null;
  if (row.pelangganId == null) return null;
  return ref.watch(pelangganByIdProvider(row.pelangganId!).future);
});

/// Jumlah transaksi yang belum tersinkron ke server. Aliran dari basis data lokal, jadi ikut berubah saat transaksi
/// offline baru tercatat dan saat sinkron selesai (dulu FutureProvider satu-shot yang basi).
final transaksiBelumSyncCountProvider = StreamProvider<int>((ref) {
  return ref.watch(transaksiDaoProvider).watchJumlahBelumSync();
});

/// F3.E - pesanan tersimpan (open bill) di outlet ini, SELALU per-HP
/// (lihat TransaksiRepository.watchPesananTersimpan).
final pesananTersimpanProvider = StreamProvider<List<TransaksiRow>>((ref) {
  final outletId = ref.watch(currentOutletIdProvider);
  return ref.watch(transaksiRepositoryProvider).watchPesananTersimpan(outletId);
});
