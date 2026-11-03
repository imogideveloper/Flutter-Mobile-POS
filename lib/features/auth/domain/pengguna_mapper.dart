import '../../../core/database/pengguna_dao.dart';
import 'pengguna.dart';

extension PenggunaDenganRoleMapper on PenggunaDenganRole {
  Pengguna toDomain() => Pengguna(
        id: pengguna.id,
        tokoId: pengguna.tokoId,
        roleId: pengguna.roleId,
        roleNama: role.nama,
        nama: pengguna.nama,
        aktif: pengguna.aktif,
      );
}
