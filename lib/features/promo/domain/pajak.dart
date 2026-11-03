import '../data/local/tables/pajak_table.dart' show PajakTipe;

class Pajak {
  const Pajak({
    required this.id,
    required this.tokoId,
    required this.nama,
    required this.tipe,
    required this.persen,
    required this.termasukHarga,
    required this.urutan,
    required this.aktif,
  });

  final String id;
  final String tokoId;
  final String nama;
  final PajakTipe tipe;
  final double persen;
  final bool termasukHarga;
  final int urutan;
  final bool aktif;
}
