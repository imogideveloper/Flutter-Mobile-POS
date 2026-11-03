class Pengguna {
  const Pengguna({
    required this.id,
    required this.tokoId,
    required this.roleId,
    required this.roleNama,
    required this.nama,
    required this.aktif,
  });

  final String id;
  final String tokoId;
  final String roleId;
  final String roleNama;
  final String nama;
  final bool aktif;
}
