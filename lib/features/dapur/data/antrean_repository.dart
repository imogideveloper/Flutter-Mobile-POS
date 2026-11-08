import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/utils/clock.dart';

/// Nomor antrian yang dibuat HP sendiri, SAAT OFFLINE (dokumen IMOGI no. 34,
/// "Nomor antrian"): urut per hari, per outlet, per perangkat, dimulai lagi
/// tiap hari. Bentuk "A-001" (awalan + tiga digit) - sama dengan format di
/// backend (`format_nomor_antrean` di order_service.py).
///
/// Disimpan di tabel `antrean_harian` (kunci outlet + perangkat + tanggal).
/// Dipanggil DI DALAM transaction checkout supaya nomor tidak pernah
/// terlewat bila checkout gagal.
class AntreanRepository {
  AntreanRepository(this._db);

  final AppDatabase _db;

  /// Awalan bawaan IMOGI: "A" (A-001). Pengaturan awalan dan angka awal
  /// per outlet belum ada layarnya.
  static const awalanBawaan = 'A';

  /// "A-001"; tanpa awalan hanya "001". Lewat 999 terus bertambah (A-1000).
  static String format(String awalan, int nomor) {
    final angka = nomor.toString().padLeft(3, '0');
    return awalan.isEmpty ? angka : '$awalan-$angka';
  }

  /// Kunci hari = tengah malam waktu setempat (bukan UTC), supaya nomor
  /// mulai lagi saat hari berganti di toko, bukan di London.
  static int kunciHari(DateTime waktu) => DateTime(waktu.year, waktu.month, waktu.day).millisecondsSinceEpoch;

  Future<String> nomorBerikutnya({
    required String outletId,
    required String perangkatId,
    required DateTime waktu,
    String awalan = awalanBawaan,
    int mulaiDari = 1,
  }) {
    final tanggal = kunciHari(waktu);
    return _db.transaction(() async {
      final baris = await (_db.select(_db.antreanHarian)
            ..where((t) => t.outletId.equals(outletId) & t.perangkatId.equals(perangkatId) & t.tanggal.equals(tanggal)))
          .getSingleOrNull();
      final nomor = baris == null ? mulaiDari : baris.nomorTerakhir + 1;
      final sekarang = nowEpochMs();
      await _db.into(_db.antreanHarian).insertOnConflictUpdate(
            AntreanHarianCompanion(
              outletId: Value(outletId),
              perangkatId: Value(perangkatId),
              tanggal: Value(tanggal),
              prefix: Value(awalan),
              nomorTerakhir: Value(nomor),
              createdAt: Value(baris?.createdAt ?? sekarang),
              updatedAt: Value(sekarang),
            ),
          );
      return format(awalan, nomor);
    });
  }
}
