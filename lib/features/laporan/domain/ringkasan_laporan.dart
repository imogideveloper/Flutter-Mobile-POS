/// Hasil agregasi utk satu periode (hari ini/7 hari/30 hari) di layar
/// Laporan - semua dihitung dari data transaksi+item+pembayaran yang sudah
/// ada, tidak ada tabel baru.
class RingkasanLaporan {
  const RingkasanLaporan({
    required this.penjualanBersih,
    required this.labaKotor,
    required this.jumlahTransaksi,
    required this.jamRamai,
    required this.metodeBayar,
    required this.produkTerlaris,
  });

  final int penjualanBersih;
  final int labaKotor;
  final int jumlahTransaksi;
  final List<JamRamai> jamRamai;
  final List<MetodeBayarPersen> metodeBayar;
  final List<ProdukTerlaris> produkTerlaris;

  int get rataRata => jumlahTransaksi == 0 ? 0 : (penjualanBersih / jumlahTransaksi).round();
}

class JamRamai {
  const JamRamai({required this.jam, required this.total});
  final int jam;
  final int total;
}

class MetodeBayarPersen {
  const MetodeBayarPersen({
    required this.metodeBayarId,
    required this.total,
    required this.persen,
    this.labelOverride,
  });
  final String metodeBayarId;
  final int total;
  final double persen;
  // Temuan A.1 (tahap 5) - diisi "QRIS manual (belum terverifikasi)" kalau
  // baris ini murni dari penanda QRIS statis/manual (lihat
  // LaporanRepository._labelPembayaran) - null = pakai nama metode bayar
  // biasa (resolve metodeBayarId spt sebelumnya, tidak berubah).
  final String? labelOverride;
}

class ProdukTerlaris {
  const ProdukTerlaris({required this.namaProduk, required this.qty, required this.total});
  final String namaProduk;
  final double qty;
  final int total;
}
