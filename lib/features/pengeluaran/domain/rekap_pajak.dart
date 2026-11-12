/// Rekap pajak PPN/PB1/service (IMOGI no. 73) dan estimasi PPh Final UMKM (no. 70) dari server.
int _rp(Object? nilai) => switch (nilai) {
      num n => n.round(),
      String s => double.parse(s).round(),
      _ => 0,
    };

class BarisPajak {
  const BarisPajak({
    required this.nama,
    required this.tipe,
    required this.persen,
    required this.jumlahTransaksi,
    required this.total,
  });

  factory BarisPajak.dariJson(Map<String, dynamic> j) => BarisPajak(
        nama: j['nama'] as String,
        tipe: j['tipe'] as String,
        persen: double.parse('${j['persen']}'),
        jumlahTransaksi: (j['jumlah_transaksi'] as num).toInt(),
        total: _rp(j['total']),
      );

  final String nama;
  final String tipe;
  final double persen;
  final int jumlahTransaksi;
  final int total;
  bool get service => tipe == 'service';
}

class RekapPajak {
  const RekapPajak({
    required this.baris,
    required this.totalPajak,
    required this.totalService,
    required this.jumlahTransaksi,
  });

  factory RekapPajak.dariJson(Map<String, dynamic> j) => RekapPajak(
        baris: [
          for (final b in (j['baris'] as List? ?? const [])) BarisPajak.dariJson(b as Map<String, dynamic>),
        ],
        totalPajak: _rp(j['total_pajak']),
        totalService: _rp(j['total_service']),
        jumlahTransaksi: (j['jumlah_transaksi'] as num).toInt(),
      );

  final List<BarisPajak> baris;
  final int totalPajak;
  final int totalService;
  final int jumlahTransaksi;
}

class PphFinalBulan {
  const PphFinalBulan({required this.bulan, required this.omzet, required this.pph});

  final String bulan;
  final int omzet;
  final int pph;
}

class PphFinal {
  const PphFinal({
    required this.tarifPersen,
    required this.omzet,
    required this.pphTerutang,
    required this.perBulan,
  });

  factory PphFinal.dariJson(Map<String, dynamic> j) => PphFinal(
        tarifPersen: double.parse('${j['tarif_persen']}'),
        omzet: _rp(j['omzet']),
        pphTerutang: _rp(j['pph_terutang']),
        perBulan: [
          for (final b in (j['per_bulan'] as List? ?? const []))
            PphFinalBulan(
              bulan: (b as Map<String, dynamic>)['bulan'] as String,
              omzet: _rp(b['omzet']),
              pph: _rp(b['pph']),
            ),
        ],
      );

  final double tarifPersen;
  final int omzet;
  final int pphTerutang;
  final List<PphFinalBulan> perBulan;
}
