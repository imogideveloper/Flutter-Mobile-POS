import 'package:apps_pos/core/network/nama_fitur.dart';
import 'package:apps_pos/core/providers/toko_profile_provider.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fondasi IMOGI (2026-11-08): mode bisnis = 7 jenis usaha Makanan & Minuman
/// dengan kode IMOGI sebagai kontrak ke backend/dashboard.
void main() {
  test('ada tepat 7 jenis usaha Makanan & Minuman dengan kode IMOGI', () {
    expect(
      {for (final j in JenisUsaha.values) j.kode: j.label},
      {
        'CAF': 'Kafe & Kedai Kopi',
        'RES': 'Restoran',
        'CAT': 'Katering',
        'BRD': 'Roti, Kue & Camilan',
        'FRZ': 'Bahan Segar & Makanan Beku',
        'BEV': 'Minuman',
        'STL': 'Kios & Food Court',
      },
    );
  });

  test('dariKode menerima kode IMOGI (huruf besar atau kecil) dan nama enum', () {
    expect(JenisUsaha.dariKode('BEV'), JenisUsaha.minuman);
    expect(JenisUsaha.dariKode('bev'), JenisUsaha.minuman);
    expect(JenisUsaha.dariKode('kios'), JenisUsaha.kios);
    expect(JenisUsaha.dariKode(' RES '), JenisUsaha.restoran);
  });

  test('nilai lama (fnb, retail) dan nilai kosong atau tak dikenal jatuh ke Kafe & Kedai Kopi', () {
    expect(JenisUsaha.dariKode('fnb'), JenisUsaha.kafe);
    expect(JenisUsaha.dariKode('retail'), JenisUsaha.kafe);
    expect(JenisUsaha.dariKode(null), JenisUsaha.kafe);
    expect(JenisUsaha.dariKode(''), JenisUsaha.kafe);
  });

  test('labelJenisUsaha lama tetap tersedia untuk semua jenis', () {
    expect(labelJenisUsaha.length, JenisUsaha.values.length);
    expect(labelJenisUsaha[JenisUsaha.kafe], 'Kafe & Kedai Kopi');
  });

  test('nama tampilan fitur mencakup fitur IMOGI baru dan tetap mempertahankan kode lama', () {
    expect(namaTampilanFitur('kasbon'), 'Bayar dengan utang (kasbon)');
    expect(namaTampilanFitur('tiket_dapur'), 'Cetak tiket dapur');
    // Fitur IMOGI baru (kode = kunci IMOGI dengan garis bawah).
    expect(namaTampilanFitur('hold'), 'Simpan pesanan (hold / open bill)');
    expect(namaTampilanFitur('journal'), 'Chart of Accounts & jurnal umum');
    // 32 kode lama + 55 kode baru = 87 fitur.
    expect(namaFitur.length, 87);
  });
}
