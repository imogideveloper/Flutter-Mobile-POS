/// Satu baris pembayaran dlm split payment (fitur F3.A - mis. separo tunai
/// separo kartu dlm satu transaksi). `nomorReferensi`/`empatDigitAkhirKartu`
/// opsional, DILARANG diisi nomor kartu lengkap.
class SplitPembayaran {
  const SplitPembayaran({
    required this.metodeBayarId,
    required this.jumlah,
    this.nomorReferensi,
    this.empatDigitAkhirKartu,
    this.labelTujuan,
  });

  final String metodeBayarId;
  final int jumlah;
  final String? nomorReferensi;
  final String? empatDigitAkhirKartu;

  /// Label tujuan terpilih (IMOGI no. 18), mis. GoPay; ikut payload_gateway dan laporan.
  final String? labelTujuan;
}
