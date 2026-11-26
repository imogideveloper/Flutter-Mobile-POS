import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/features/laporan/data/laporan_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// "Hari ini" di Laporan mulai pukul 00.00 jam HP, bukan 00.00 UTC (temuan HP 2026-11-26: transaksi 06.52 WIB
/// tidak muncul di Hari ini karena masih tanggal kemarin menurut UTC).
void main() {
  test('periode laporan memakai batas hari jam HP', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = LaporanRepository(db.transaksiDao);
    final sekarang = DateTime.now();
    final (awal, akhir) = repo.rentang(PeriodeLaporan.hariIni);
    expect(awal, DateTime(sekarang.year, sekarang.month, sekarang.day).millisecondsSinceEpoch);
    expect(akhir, DateTime(sekarang.year, sekarang.month, sekarang.day + 1).millisecondsSinceEpoch);

    final (awalCustom, akhirCustom) =
        repo.rentang(PeriodeLaporan.custom, rentangCustom: (DateTime(2026, 11, 26), DateTime(2026, 11, 26)));
    expect(awalCustom, DateTime(2026, 11, 26).millisecondsSinceEpoch);
    expect(akhirCustom, DateTime(2026, 11, 27).millisecondsSinceEpoch);
  });
}
