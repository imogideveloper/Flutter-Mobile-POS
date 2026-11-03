import 'package:drift/drift.dart';

import 'app_database.dart';
import 'tables/outlets_table.dart';
import 'tables/perangkat_table.dart';

part 'pairing_dao.g.dart';

/// Menulis hasil pairing OTP (lihat otp_login_page.dart + AuthSessionStore)
/// ke tabel Outlets/Perangkat lokal - dipisah dari ProdukDao/dll krn kedua
/// tabel ini sebelumnya tidak punya DAO sama sekali (outlet-default yang
/// dipakai session_provider.dart sebagai placeholder bahkan tidak pernah
/// punya baris sungguhan di SQLite lokal sampai sekarang).
@DriftAccessor(tables: [Outlets, Perangkat])
class PairingDao extends DatabaseAccessor<AppDatabase> with _$PairingDaoMixin {
  PairingDao(super.db);

  Future<void> upsertOutlet(OutletsCompanion data) =>
      into(outlets).insertOnConflictUpdate(data);

  Future<void> upsertPerangkat(PerangkatCompanion data) =>
      into(perangkat).insertOnConflictUpdate(data);

  /// Tabel-tabel (di LUAR accessor ini) yang punya kolom toko_id - dipakai
  /// `migrasikanTokoId` di bawah. Daftar ini HARUS ikut diperbarui kalau
  /// ada tabel baru dengan kolom toko_id ditambahkan nanti (tidak otomatis
  /// terdeteksi krn ditulis manual, bukan introspeksi skema).
  static const _tabelDenganTokoId = [
    'absensi', 'survei', 'promo', 'pajak', 'aturan_poin', 'pelanggan',
    'level_member', 'kategori', 'pengguna', 'role', 'mutasi_stok',
    'transaksi', 'produk', 'tipe_order', 'shift', 'metode_bayar',
    'grup_modifier', 'satuan', 'perangkat', 'outlet',
  ];

  /// Dipanggil sekali setelah pairing OTP sukses - toko_id SEMUA baris
  /// lokal (yang sebelumnya ditulis pakai placeholder 'toko-default' saat
  /// device belum pernah pairing, lihat session_provider.dart) diganti ke
  /// id ASLI dari backend, supaya data yang sudah dibuat offline sebelum
  /// pairing (device BISA dipakai tanpa pairing lewat tombol "Masuk dengan
  /// PIN karyawan" di OtpLoginPage) tetap konsisten dgn id yang nanti
  /// dikirim di payload /sync/push & dipakai provider sesi.
  Future<void> migrasikanTokoId({required String dari, required String ke}) {
    if (dari == ke) return Future.value();
    return transaction(() async {
      for (final tabel in _tabelDenganTokoId) {
        await customStatement(
          'UPDATE $tabel SET toko_id = ? WHERE toko_id = ?',
          [ke, dari],
        );
      }
    });
  }
}
