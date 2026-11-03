import 'package:drift/drift.dart';

import 'app_database.dart';
import 'tables/pengguna_table.dart';
import 'tables/role_izin_sync_table.dart';
import 'tables/role_table.dart';

part 'pengguna_dao.g.dart';

class PenggunaDenganRole {
  const PenggunaDenganRole({required this.pengguna, required this.role});

  final PenggunaRow pengguna;
  final RoleRow role;
}

@DriftAccessor(tables: [Pengguna, Role, RoleIzinSync])
class PenggunaDao extends DatabaseAccessor<AppDatabase> with _$PenggunaDaoMixin {
  PenggunaDao(super.db);

  Stream<List<PenggunaDenganRole>> watchPenggunaAktif(String tokoId) {
    final query = select(pengguna).join([
      innerJoin(role, role.id.equalsExp(pengguna.roleId)),
    ])
      ..where(pengguna.tokoId.equals(tokoId) &
          pengguna.aktif.equals(true) &
          pengguna.deletedAt.isNull());

    return query.watch().map((rows) => rows
        .map((row) => PenggunaDenganRole(
              pengguna: row.readTable(pengguna),
              role: row.readTable(role),
            ))
        .toList());
  }

  Stream<List<RoleRow>> watchRoleBawaan() =>
      (select(role)..where((t) => t.isSystem.equals(true))).watch();

  Future<PenggunaRow?> cariById(String id) =>
      (select(pengguna)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<void> tambahPengguna(PenggunaCompanion data) =>
      into(pengguna).insert(data);

  Future<void> updatePengguna(String id, PenggunaCompanion data) =>
      (update(pengguna)..where((t) => t.id.equals(id))).write(data);

  Future<RoleRow?> cariRoleOwner() =>
      (select(role)..where((t) => t.nama.equals('Owner') & t.isSystem.equals(true)))
          .getSingleOrNull();

  /// Pengguna pertama dengan role Owner di toko ini - dipakai alur Daftar
  /// utk tahu apakah perlu UPDATE Owner hasil seed (lihat seed.dart) atau
  /// INSERT baru (seharusnya jarang kejadian, seed selalu jalan duluan).
  Future<PenggunaRow?> cariOwnerUtama(String tokoId) async {
    final query = select(pengguna).join([
      innerJoin(role, role.id.equalsExp(pengguna.roleId)),
    ])
      ..where(pengguna.tokoId.equals(tokoId) &
          role.nama.equals('Owner') &
          role.isSystem.equals(true) &
          pengguna.deletedAt.isNull())
      ..limit(1);
    final row = await query.getSingleOrNull();
    return row?.readTable(pengguna);
  }

  /// Sama seperti [cariOwnerUtama] tapi TANPA filter tokoId - fallback utk
  /// device yang baris Owner lokalnya sudah pernah dimigrasikan ke tokoId
  /// lain oleh percobaan pairing sebelumnya yang gagal di tengah jalan
  /// (mis. berhasil di backend tapi error lokal sebelum sempat tandai
  /// device paired) - lihat terapkanIdentitasBackend. Device cuma pernah
  /// punya SATU baris Owner lokal, jadi aman diambil tanpa scope tokoId.
  /// Tahap 5 C.4 - penjaga lokal "tidak bisa nonaktifkan Owner terakhir",
  /// mirror dari aturan yang sama di backend (_jumlah_owner_aktif_lain) -
  /// role/pengguna lokal TIDAK match UUID backend, jadi aturan ini wajib
  /// diimplementasikan ulang di sisi Dart, bukan dipanggil dari server.
  Future<int> jumlahOwnerAktif(String tokoId) async {
    final query = select(pengguna).join([
      innerJoin(role, role.id.equalsExp(pengguna.roleId)),
    ])
      ..where(pengguna.tokoId.equals(tokoId) &
          pengguna.aktif.equals(true) &
          pengguna.deletedAt.isNull() &
          role.nama.equals('Owner') &
          role.isSystem.equals(true));
    final rows = await query.get();
    return rows.length;
  }

  /// Tahap 5b (desain #3) - lockout 5x PIN salah.
  Future<void> catatPercobaanGagal(String id, int percobaanBaru) =>
      (update(pengguna)..where((t) => t.id.equals(id)))
          .write(PenggunaCompanion(percobaanGagal: Value(percobaanBaru)));

  Future<void> kunciSementara(String id, {required int sampaiEpochMs}) =>
      (update(pengguna)..where((t) => t.id.equals(id))).write(
        PenggunaCompanion(percobaanGagal: const Value(0), terkunciSampai: Value(sampaiEpochMs)),
      );

  Future<void> resetPercobaanGagal(String id) => (update(pengguna)..where((t) => t.id.equals(id)))
      .write(const PenggunaCompanion(percobaanGagal: Value(0), terkunciSampai: Value(null)));

  Future<PenggunaRow?> cariOwnerManaSaja() async {
    final query = select(pengguna).join([
      innerJoin(role, role.id.equalsExp(pengguna.roleId)),
    ])
      ..where(role.nama.equals('Owner') &
          role.isSystem.equals(true) &
          pengguna.deletedAt.isNull())
      ..orderBy([OrderingTerm.asc(pengguna.createdAt)])
      ..limit(1);
    final row = await query.getSingleOrNull();
    return row?.readTable(pengguna);
  }

  // --- Tahap 5b (desain #2) - upsert dari /sync/pull. ---

  Future<void> upsertRole(RoleCompanion data) => into(role).insertOnConflictUpdate(data);

  Future<void> upsertRoleIzinSync(RoleIzinSyncCompanion data) =>
      into(roleIzinSync).insertOnConflictUpdate(data);

  /// BEDA dari [updatePengguna]/[tambahPengguna] (dipakai layar kelola
  /// karyawan LOKAL lama) - ini KHUSUS data yang datang dari server, jadi
  /// insertOnConflictUpdate (upsert, bukan insert-only) dan SENGAJA tidak
  /// menyertakan percobaanGagal/terkunciSampai di Companion supaya kolom
  /// lockout PIN (murni lokal) tidak ketiban nilai server tiap sync.
  Future<void> upsertPenggunaDariSync(PenggunaCompanion data) =>
      into(pengguna).insertOnConflictUpdate(data);
}
