import '../../../core/database/app_database.dart';
import 'pelanggan.dart' as domain;

extension PelangganRowMapper on PelangganRow {
  domain.Pelanggan toDomain() => domain.Pelanggan(
        id: id,
        tokoId: tokoId,
        nama: nama,
        noHp: noHp,
        email: email,
        levelMemberId: levelMemberId,
        poin: poin,
        totalBelanja: totalBelanja,
        catatan: catatan,
        batasKasbon: batasKasbon,
        tanggalLahir: tanggalLahir,
      );
}

extension LevelMemberRowMapper on LevelMemberRow {
  domain.LevelMember toDomain() => domain.LevelMember(
        id: id,
        tokoId: tokoId,
        nama: nama,
        minTotalBelanja: minTotalBelanja,
        diskonPersen: diskonPersen,
        pengaliPoin: pengaliPoin,
        urutan: urutan,
      );
}

extension AturanPoinRowMapper on AturanPoinRow {
  domain.AturanPoin toDomain() => domain.AturanPoin(
        nominalPerPoin: nominalPerPoin,
        nilaiTukarPoin: nilaiTukarPoin,
        minTukarPoin: minTukarPoin,
        kedaluwarsaHari: kedaluwarsaHari,
        aktif: aktif,
      );
}
