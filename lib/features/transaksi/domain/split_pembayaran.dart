/// Satu baris pembayaran dlm split payment (fitur F3.A - mis. separo tunai
/// separo kartu dlm satu transaksi). `nomorReferensi`/`empatDigitAkhirKartu`
/// opsional, DILARANG diisi nomor kartu lengkap.
class SplitPembayaran {
  const SplitPembayaran({
    required this.metodeBayarId,
    required this.jumlah,
    this.nomorReferensi,
    this.empatDigitAkhirKartu,
  });

  final String metodeBayarId;
  final int jumlah;
  final String? nomorReferensi;
  final String? empatDigitAkhirKartu;
}
