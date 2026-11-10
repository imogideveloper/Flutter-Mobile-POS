class Kategori {
  const Kategori({
    required this.id,
    required this.tokoId,
    required this.nama,
    required this.warna,
    required this.urutan,
    this.masukTiketDapur = true,
  });

  final String id;
  final String tokoId;
  final String nama;
  final String? warna;
  final int urutan;
  final bool masukTiketDapur;
}
