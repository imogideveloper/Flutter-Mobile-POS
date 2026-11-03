class Meja {
  const Meja({
    required this.id,
    required this.outletId,
    required this.nama,
    this.area,
    this.kapasitas,
    required this.urutan,
    required this.aktif,
  });

  final String id;
  final String outletId;
  final String nama;
  final String? area;
  final int? kapasitas;
  final int urutan;
  final bool aktif;
}
