import '../../../core/providers/toko_profile_provider.dart';

/// Nilai rekomendasi pengaturan outlet dan struk menurut jenis usaha (panduan IMOGI, bagian bawaan
/// per jenis usaha). Dipakai tombol "Kembalikan ke rekomendasi" di Pengaturan outlet dan struk.
/// FUNGSI MURNI supaya bisa diuji tanpa layar.
class RekomendasiOutlet {
  const RekomendasiOutlet({
    required this.footerStruk,
    required this.lebarKertasMm,
    required this.tampilLogo,
    required this.strukRingkas,
    required this.pakaiNomorAntrean,
    required this.antreanAwalan,
    required this.antreanMulai,
    required this.estimasiMenit,
    required this.batasMargin,
    required this.pembulatan,
    required this.izinkanStokMinus,
  });

  final String footerStruk;
  final int lebarKertasMm;
  final bool tampilLogo;
  final bool strukRingkas;
  final bool pakaiNomorAntrean;
  final String antreanAwalan;
  final int antreanMulai;
  final int estimasiMenit;
  final int batasMargin;
  final int pembulatan;
  final bool izinkanStokMinus;
}

/// Jenis usaha yang bawaannya struk ringkas dan nomor antrean menyala (kafe, roti, minuman, food court).
const _jenisCepatSaji = {JenisUsaha.kafe, JenisUsaha.roti, JenisUsaha.minuman, JenisUsaha.kios};

RekomendasiOutlet rekomendasiOutlet(JenisUsaha jenis) {
  final cepat = _jenisCepatSaji.contains(jenis);
  return RekomendasiOutlet(
    footerStruk: 'Terima kasih, selamat menikmati!',
    lebarKertasMm: 58,
    tampilLogo: false,
    strukRingkas: cepat,
    pakaiNomorAntrean: cepat,
    antreanAwalan: 'A',
    antreanMulai: 1,
    estimasiMenit: 0,
    batasMargin: 50,
    pembulatan: 0,
    // Kafe dan restoran mengatur stok sendiri; jenis lain tetap boleh jual walau stok habis.
    izinkanStokMinus: true,
  );
}
