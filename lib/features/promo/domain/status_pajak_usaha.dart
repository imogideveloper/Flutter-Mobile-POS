import '../data/local/tables/pajak_table.dart' show PajakTipe;
import 'pajak.dart';

/// Status pajak usaha (IMOGI no. 4): usaha dianggap **kena pajak** bila ada
/// minimal satu pajak (bukan service charge) yang aktif, **tidak kena pajak**
/// bila pajak ada tetapi semuanya nonaktif, dan **belum diatur** bila belum
/// ada pajak sama sekali. Service charge tidak ikut dihitung.
enum StatusPajakUsaha { belumDiatur, kena, tidakKena }

StatusPajakUsaha statusPajakUsaha(List<Pajak> semua) {
  final pajak = semua.where((p) => p.tipe == PajakTipe.pajak).toList();
  if (pajak.isEmpty) return StatusPajakUsaha.belumDiatur;
  return pajak.any((p) => p.aktif) ? StatusPajakUsaha.kena : StatusPajakUsaha.tidakKena;
}

/// Isian cepat untuk form tambah pajak: nama yang umum di F&B beserta
/// nilai bawaannya. Nilai bisa diubah sebelum disimpan.
class PresetPajak {
  const PresetPajak({
    required this.label,
    required this.nama,
    required this.persen,
    required this.tipe,
    this.termasukHarga = false,
  });

  final String label;
  final String nama;
  final double persen;
  final PajakTipe tipe;
  final bool termasukHarga;
}

const daftarPresetPajak = [
  PresetPajak(label: 'PB1 10%', nama: 'PB1', persen: 10, tipe: PajakTipe.pajak),
  PresetPajak(label: 'PPN 11%', nama: 'PPN', persen: 11, tipe: PajakTipe.pajak),
  PresetPajak(label: 'Service 5%', nama: 'Service', persen: 5, tipe: PajakTipe.service),
];
