import 'package:drift/drift.dart';

import 'role_table.dart';

/// Cache lokal data pengguna untuk login cepat & cek nama di struk/riwayat.
/// Tanpa password_hash - password selalu divalidasi lewat server, PIN lokal
/// dipakai hanya untuk approval aksi sensitif (void, refund, diskon manual).
@DataClassName('PenggunaRow')
class Pengguna extends Table {
  @override
  String get tableName => 'pengguna';

  TextColumn get id => text()();
  TextColumn get tokoId => text()();
  TextColumn get roleId => text().references(Role, #id)();
  TextColumn get nama => text()();
  TextColumn get email => text().nullable()();
  TextColumn get noHp => text().nullable()();
  TextColumn get pinHash => text().nullable()();
  BoolColumn get aktif => boolean().withDefault(const Constant(true))();
  IntColumn get terakhirLogin => integer().nullable()();
  // Tahap 5b - "karyawan = baris pengguna server". Utk baris yang DATANG
  // dari /sync/pull, nilainya SAMA dgn `id` (sudah identitas server sejak
  // awal). Utk karyawan LAMA yang dibuat lokal sebelum tahap ini (id-nya
  // belum dikenal server), tetap null sampai migrasi 1x berhasil push ke
  // server (lihat PenggunaRepository.migrasikanKaryawanLokalKeServer) -
  // `id` lokal TIDAK PERNAH ditulis ulang (supaya semua FK lokal yang
  // sudah menunjuk ke baris ini - transaksi/shift/kas_shift/dkk - tidak
  // perlu migrasi massal), cukup kolom ini yang mencatat "id server-nya
  // yang sebenarnya" dipakai saat menyusun payload push.
  TextColumn get serverPenggunaId => text().nullable()();
  // Lockout 5x PIN salah (desain #3) - direset ke 0/null begitu PIN benar.
  IntColumn get percobaanGagal => integer().withDefault(const Constant(0))();
  IntColumn get terkunciSampai => integer().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
