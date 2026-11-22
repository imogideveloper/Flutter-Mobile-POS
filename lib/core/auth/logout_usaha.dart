import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart';
import '../network/auth_session_store.dart';
import '../network/dio_backend_api.dart';
import '../network/sync_repository.dart';
import '../providers/database_provider.dart';
import '../providers/device_pairing_provider.dart';
import '../providers/seed_provider.dart';
import '../providers/toko_profile_provider.dart';
import '../providers/session_provider.dart';

enum HasilLogoutUsaha {
  /// Sesi, pairing, dan data lokal sudah dihapus; aplikasi kembali ke layar daftar/OTP.
  berhasil,

  /// Masih ada data yang belum terkirim ke server - logout ditahan supaya tidak hilang.
  belumSinkron,
}

/// Jumlah data lokal yang belum sampai ke server (transaksi, pembayaran
/// susulan, pembatalan pesanan, status pesanan). Bila > 0, keluar dari
/// usaha akan MENGHILANGKAN data itu, jadi logout ditahan.
Future<int> hitungBelumTersinkron(AppDatabase db) async {
  final dao = db.transaksiDao;
  final transaksi = await dao.transaksiBelumSync();
  final pembayaran = await dao.pembayaranBelumSync();
  final pembatalan = await dao.pembatalanPesananBelumSync();
  final status = await dao.statusPesananBelumSync();
  return transaksi.length + pembayaran.length + pembatalan.length + status.length;
}

/// Keluar dari usaha (IMOGI/lead: sebelumnya sekali pairing tidak bisa
/// logout). Urutan: (1) coba sync terakhir, (2) tahan bila masih ada data
/// belum terkirim, (3) cabut perangkat di server (best-effort - offline
/// tidak menghalangi), (4) hapus token + tanda pairing + data lokal usaha,
/// (5) kembalikan sesi memori ke placeholder dan seed ulang bawaan.
Future<HasilLogoutUsaha> keluarDariUsaha(WidgetRef ref) async {
  final db = ref.read(appDatabaseProvider);

  try {
    await ref.read(syncRepositoryProvider).jalankan();
  } catch (_) {
    // Offline/gagal sync: hasilnya ditentukan oleh hitungan di bawah.
  }
  if (await hitungBelumTersinkron(db) > 0) return HasilLogoutUsaha.belumSinkron;

  final store = ref.read(authSessionStoreProvider);
  final sesi = await store.muat();
  if (sesi != null) {
    try {
      await ref.read(backendApiProvider).postJson(accessToken: sesi.accessToken, path: '/auth/logout');
    } catch (_) {
      // Token lokal tetap dihapus; server mencabut hanya bila terjangkau.
    }
  }

  await store.hapus();
  await hapusTandaPaired(ref);
  await hapusTokoProfile(ref);
  await db.hapusSemuaDataLokal();

  ref.read(currentPenggunaIdProvider.notifier).logout();
  ref.read(currentTokoIdProvider.notifier).set(tokoIdPlaceholder);
  ref.read(currentOutletIdProvider.notifier).set(outletIdPlaceholder);
  ref.read(currentPerangkatIdProvider.notifier).set(perangkatIdPlaceholder);
  ref.invalidate(devicePairedProvider);
  ref.invalidate(authBootstrapProvider);
  ref.invalidate(seedProvider);
  return HasilLogoutUsaha.berhasil;
}
