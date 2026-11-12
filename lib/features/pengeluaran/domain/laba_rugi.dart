/// Laporan laba rugi (IMOGI no. 69) dari server. Nilai uang berupa string desimal dari server.
class LabaRugi {
  const LabaRugi({
    required this.penjualanKotor,
    required this.diskon,
    required this.penjualanBersih,
    required this.hpp,
    required this.labaKotor,
    required this.biayaOperasional,
    required this.totalBiayaOperasional,
    required this.labaBersih,
    required this.belanjaBahan,
    required this.pajakDipungut,
    required this.jumlahTransaksi,
  });

  factory LabaRugi.dariJson(Map<String, dynamic> j) => LabaRugi(
        penjualanKotor: _rp(j['penjualan_kotor']),
        diskon: _rp(j['diskon']),
        penjualanBersih: _rp(j['penjualan_bersih']),
        hpp: _rp(j['hpp']),
        labaKotor: _rp(j['laba_kotor']),
        biayaOperasional: {
          for (final b in (j['biaya_operasional'] as List? ?? const []))
            (b as Map<String, dynamic>)['kategori'] as String: _rp(b['total']),
        },
        totalBiayaOperasional: _rp(j['total_biaya_operasional']),
        labaBersih: _rp(j['laba_bersih']),
        belanjaBahan: _rp(j['belanja_bahan']),
        pajakDipungut: _rp(j['pajak_dipungut']),
        jumlahTransaksi: (j['jumlah_transaksi'] as num).toInt(),
      );

  final int penjualanKotor;
  final int diskon;
  final int penjualanBersih;
  final int hpp;
  final int labaKotor;
  final Map<String, int> biayaOperasional;
  final int totalBiayaOperasional;
  final int labaBersih;
  final int belanjaBahan;
  final int pajakDipungut;
  final int jumlahTransaksi;

  bool get rugi => labaBersih < 0;
}

int _rp(Object? nilai) => switch (nilai) {
      num n => n.round(),
      String s => double.parse(s).round(),
      _ => 0,
    };

/// ISO-8601 dengan offset zona waktu perangkat ("2026-11-12T00:00:00+07:00"). Server memotong
/// tanggal pengeluaran dari nilai ini, jadi offset wajib ada agar hari tidak bergeser.
String isoDenganOffset(DateTime t) {
  final lokal = t.toLocal();
  String dua(int n) => n.toString().padLeft(2, '0');
  final offset = lokal.timeZoneOffset;
  final tanda = offset.isNegative ? '-' : '+';
  final menit = offset.inMinutes.abs();
  return '${lokal.year.toString().padLeft(4, '0')}-${dua(lokal.month)}-${dua(lokal.day)}'
      'T${dua(lokal.hour)}:${dua(lokal.minute)}:${dua(lokal.second)}'
      '$tanda${dua(menit ~/ 60)}:${dua(menit % 60)}';
}
