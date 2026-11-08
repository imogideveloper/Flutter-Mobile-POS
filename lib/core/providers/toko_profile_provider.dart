import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'device_pairing_provider.dart';

/// Jenis usaha: HANYA modul Makanan & Minuman dari dokumen IMOGI (IMOGI POS
/// Menu & Fitur, 5 Nov 2026). `kode` = kode jenis usaha IMOGI (3 huruf), itu
/// yang dikirim ke backend dan disimpan di `toko.jenis_usaha` sebagai kontrak
/// dengan dashboard. Jenis usaha nanti menentukan nilai bawaan pengaturan dan
/// bagian yang tampil (utama/opsional/tidak relevan).
enum JenisUsaha {
  kafe('CAF', 'Kafe & Kedai Kopi'),
  restoran('RES', 'Restoran'),
  katering('CAT', 'Katering'),
  roti('BRD', 'Roti, Kue & Camilan'),
  bahanSegar('FRZ', 'Bahan Segar & Makanan Beku'),
  minuman('BEV', 'Minuman'),
  kios('STL', 'Kios & Food Court');

  const JenisUsaha(this.kode, this.label);

  final String kode;
  final String label;

  /// Dari kode IMOGI. Nilai lama versi sebelumnya ('fnb', atau nama enum
  /// lama) dan nilai tak dikenal dianggap Kafe & Kedai Kopi.
  static JenisUsaha dariKode(String? nilai) {
    if (nilai == null) return JenisUsaha.kafe;
    final n = nilai.trim();
    for (final j in JenisUsaha.values) {
      if (j.kode == n.toUpperCase() || j.name == n) return j;
    }
    return JenisUsaha.kafe;
  }
}

/// Dipertahankan untuk kode lama yang memakai peta ini.
final labelJenisUsaha = {for (final j in JenisUsaha.values) j: j.label};

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

  final jenis = JenisUsaha.dariKode(jenisStr);
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
  await storage.write(key: _kJenisUsahaKey, value: jenisUsaha.kode);
  await storage.write(key: _kNamaPemilikKey, value: namaPemilik);
  ref.invalidate(tokoProfileProvider);
}
