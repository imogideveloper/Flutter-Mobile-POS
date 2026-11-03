class Pelanggan {
  const Pelanggan({
    required this.id,
    required this.tokoId,
    required this.nama,
    this.noHp,
    this.email,
    this.levelMemberId,
    required this.poin,
    required this.totalBelanja,
    this.catatan,
    this.batasKasbon,
  });

  final String id;
  final String tokoId;
  final String nama;
  final String? noHp;
  final String? email;
  final String? levelMemberId;
  final int poin;
  final int totalBelanja;
  final String? catatan;
  // NULL = tidak ada batas kasbon (tahap 3b-1).
  final int? batasKasbon;
}

class LevelMember {
  const LevelMember({
    required this.id,
    required this.tokoId,
    required this.nama,
    required this.minTotalBelanja,
    required this.diskonPersen,
    required this.pengaliPoin,
    required this.urutan,
  });

  final String id;
  final String tokoId;
  final String nama;
  final int minTotalBelanja;
  final double diskonPersen;
  final double pengaliPoin;
  final int urutan;
}

class AturanPoin {
  const AturanPoin({
    required this.nominalPerPoin,
    required this.nilaiTukarPoin,
    required this.minTukarPoin,
    this.kedaluwarsaHari,
    required this.aktif,
  });

  final int nominalPerPoin;
  final int nilaiTukarPoin;
  final int minTukarPoin;
  final int? kedaluwarsaHari;
  final bool aktif;
}
