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
    this.marginProduk = const [],
  });

  final int penjualanBersih;
  final int labaKotor;
  final int jumlahTransaksi;
  final List<JamRamai> jamRamai;
  final List<MetodeBayarPersen> metodeBayar;
  final List<ProdukTerlaris> produkTerlaris;

  /// HPP dan margin per produk, urut laba terbesar (IMOGI no. 72); semua produk terjual, bukan 5 teratas.
  final List<MarginProdukLaporan> marginProduk;

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

/// Satu baris item terjual sebagai masukan perhitungan margin (IMOGI no. 72). [omzet] = subtotal baris
/// (harga akhir, sudah termasuk tambahan), [hpp] = HPP satuan x qty.
class BarisItemMargin {
  const BarisItemMargin({required this.nama, required this.qty, required this.omzet, required this.hpp});

  final String nama;
  final double qty;
  final int omzet;
  final int hpp;
}

/// HPP dan margin satu produk pada periode laporan (IMOGI no. 72, HPP & margin per produk).
class MarginProdukLaporan {
  const MarginProdukLaporan({required this.namaProduk, required this.qty, required this.omzet, required this.hpp});

  final String namaProduk;
  final double qty;
  final int omzet;
  final int hpp;

  int get laba => omzet - hpp;

  /// HPP belum diisi: margin tidak bisa dipercaya (bukan 100%).
  bool get hppKosong => hpp <= 0 && omzet > 0;

  /// Margin (%) = laba / omzet x 100; null bila omzet 0 atau HPP kosong.
  double? get marginPersen => (omzet <= 0 || hppKosong) ? null : laba / omzet * 100;
}

/// Menjumlahkan baris item per nama produk, urut laba terbesar lebih dulu (lalu nama). FUNGSI MURNI.
List<MarginProdukLaporan> hitungMarginProduk(Iterable<BarisItemMargin> baris) {
  final qty = <String, double>{};
  final omzet = <String, int>{};
  final hpp = <String, int>{};
  for (final b in baris) {
    qty[b.nama] = (qty[b.nama] ?? 0) + b.qty;
    omzet[b.nama] = (omzet[b.nama] ?? 0) + b.omzet;
    hpp[b.nama] = (hpp[b.nama] ?? 0) + b.hpp;
  }
  final hasil = [
    for (final nama in qty.keys)
      MarginProdukLaporan(namaProduk: nama, qty: qty[nama]!, omzet: omzet[nama]!, hpp: hpp[nama]!),
  ];
  hasil.sort((a, b) {
    final c = b.laba.compareTo(a.laba);
    return c != 0 ? c : a.namaProduk.compareTo(b.namaProduk);
  });
  return hasil;
}
