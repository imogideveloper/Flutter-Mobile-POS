import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'device_pairing_provider.dart';

/// Jenis usaha - preset ini nanti menentukan fitur yang dinyalakan default
/// (lihat dokumen tech stack bagian 4.2, `toko.pengaturan_fitur`) begitu
/// modul feature-gating dibangun. Untuk sekarang murni dipakai sebagai
/// info tampilan di halaman Daftar & Lainnya.
enum JenisUsaha { retail, fnb, jasa, laundry, fashion }

const labelJenisUsaha = {
  JenisUsaha.retail: 'Toko / Retail',
  JenisUsaha.fnb: 'Makanan & Minuman',
  JenisUsaha.jasa: 'Jasa',
  JenisUsaha.laundry: 'Laundry',
  JenisUsaha.fashion: 'Fashion',
};

/// Profil toko hasil Daftar - SENGAJA disimpan lokal (bukan di tabel drift
/// `toko`, itu memang tidak ada di SQLite HP per rencana sync, lihat
/// dokumen bagian 4.1) karena toko baru benar-benar "resmi" setelah
/// tersinkron ke backend. Dipakai murni utk tampilan (mis. kartu profil di
/// halaman Lainnya) sebelum modul sync ada.
class TokoProfile {
  const TokoProfile({
    required this.namaToko,
    required this.jenisUsaha,
    required this.namaPemilik,
  });

  final String namaToko;
  final JenisUsaha jenisUsaha;
  final String namaPemilik;
}

const _kNamaTokoKey = 'toko_profile_nama';
const _kJenisUsahaKey = 'toko_profile_jenis_usaha';
const _kNamaPemilikKey = 'toko_profile_nama_pemilik';

final tokoProfileProvider = FutureProvider<TokoProfile?>((ref) async {
  final storage = ref.watch(secureStorageProvider);
  final nama = await storage.read(key: _kNamaTokoKey);
  final jenisStr = await storage.read(key: _kJenisUsahaKey);
  final namaPemilik = await storage.read(key: _kNamaPemilikKey);
  if (nama == null || jenisStr == null || namaPemilik == null) return null;

  final jenis = JenisUsaha.values.firstWhere(
    (j) => j.name == jenisStr,
    orElse: () => JenisUsaha.retail,
  );
  return TokoProfile(namaToko: nama, jenisUsaha: jenis, namaPemilik: namaPemilik);
});

Future<void> simpanTokoProfile(
  WidgetRef ref, {
  required String namaToko,
  required JenisUsaha jenisUsaha,
  required String namaPemilik,
}) async {
  final storage = ref.read(secureStorageProvider);
  await storage.write(key: _kNamaTokoKey, value: namaToko);
  await storage.write(key: _kJenisUsahaKey, value: jenisUsaha.name);
  await storage.write(key: _kNamaPemilikKey, value: namaPemilik);
  ref.invalidate(tokoProfileProvider);
}
