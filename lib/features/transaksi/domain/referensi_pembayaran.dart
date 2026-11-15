/// Aturan "wajib no. referensi" pada pembayaran non-tunai (IMOGI no. 13).
///
/// Bila metode diatur wajib referensi: no. referensi/approval EDC harus diisi;
/// untuk kartu, 4 digit akhir kartu juga harus diisi tepat 4 angka. Bila tidak
/// wajib, isian tetap opsional tetapi 4 digit (bila diisi) harus 4 angka.
/// Mengembalikan pesan galat, atau null bila valid.
String? validasiReferensiPembayaran({
  required bool wajibReferensi,
  required bool kartu,
  required String nomorReferensi,
  required String empatDigit,
}) {
  final nomor = nomorReferensi.trim();
  final digit = empatDigit.trim();
  final digitValid = RegExp(r'^\d{4}$').hasMatch(digit);

  if (digit.isNotEmpty && !digitValid) return '4 digit akhir kartu harus tepat 4 angka';
  if (!wajibReferensi) return null;
  if (nomor.isEmpty) return 'No. referensi wajib diisi untuk metode ini';
  if (kartu && digit.isEmpty) return '4 digit akhir kartu wajib diisi';
  return null;
}
