import 'laba_rugi.dart';

/// Laba rugi satu outlet pada laporan konsolidasi.
class LabaRugiOutlet {
  const LabaRugiOutlet({required this.outletId, required this.outletNama, required this.laporan});

  final String outletId;
  final String outletNama;
  final LabaRugi laporan;
}

/// Laporan laba rugi seluruh outlet (IMOGI no. 84): per outlet plus total toko. [biayaTanpaOutlet] adalah biaya
/// yang dicatat tanpa outlet; sudah termasuk di [total] tetapi tidak ada di baris outlet mana pun.
class LabaRugiKonsolidasi {
  const LabaRugiKonsolidasi({required this.perOutlet, required this.total, required this.biayaTanpaOutlet});

  factory LabaRugiKonsolidasi.dariJson(Map<String, dynamic> j) => LabaRugiKonsolidasi(
        perOutlet: [
          for (final o in (j['per_outlet'] as List? ?? const []).cast<Map<String, dynamic>>())
            LabaRugiOutlet(
              outletId: o['outlet_id'] as String,
              outletNama: o['outlet_nama'] as String,
              laporan: LabaRugi.dariJson(o['laporan'] as Map<String, dynamic>),
            ),
        ],
        total: LabaRugi.dariJson(j['total'] as Map<String, dynamic>),
        biayaTanpaOutlet: switch (j['biaya_tanpa_outlet']) {
          num n => n.round(),
          String s => double.parse(s).round(),
          _ => 0,
        },
      );

  final List<LabaRugiOutlet> perOutlet;
  final LabaRugi total;
  final int biayaTanpaOutlet;
}
