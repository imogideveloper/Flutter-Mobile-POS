import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
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
  return ref.watch(transaksiRepositoryProvider).detailTransaksi(
        transaksiId,
        namaPelanggan: namaPelanggan,
      );
});

/// Dipisah dari [detailTransaksiProvider] supaya tidak perlu import modul
/// Pelanggan langsung ke TransaksiRepository (lihat komentar di
/// detailTransaksi) - lookup nama dilakukan di layer provider ini saja.
final namaPelangganUntukTransaksiProvider =
    FutureProvider.family<String?, String>((ref, transaksiId) async {
  final row = await ref.watch(transaksiDaoProvider).transaksiById(transaksiId);
  if (row.pelangganId == null) return null;
  return ref.watch(pelangganByIdProvider(row.pelangganId!).future);
});

/// Jumlah transaksi yang belum tersinkron ke server - selalu akurat
/// (bukan placeholder) karena belum ada mekanisme sync sama sekali di
/// tahap ini, jadi semua transaksi lokal memang masih menunggu.
final transaksiBelumSyncCountProvider = FutureProvider<int>((ref) async {
  final rows = await ref.watch(transaksiDaoProvider).transaksiBelumSync();
  return rows.length;
});

/// F3.E - pesanan tersimpan (open bill) di outlet ini, SELALU per-HP
/// (lihat TransaksiRepository.watchPesananTersimpan).
final pesananTersimpanProvider = StreamProvider<List<TransaksiRow>>((ref) {
  final outletId = ref.watch(currentOutletIdProvider);
  return ref.watch(transaksiRepositoryProvider).watchPesananTersimpan(outletId);
});
