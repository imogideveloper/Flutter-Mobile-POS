import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/features/transaksi/data/local/tables/transaksi_table.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ditemukan di HP 2026-11-23: dua penjualan offline tersimpan dengan disinkron_pada kosong, tetapi layar Lainnya
/// tetap menulis "Semua transaksi tersinkron" karena hitungannya diambil sekali (FutureProvider satu-shot).
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> catat(String id, {TransaksiStatus status = TransaksiStatus.selesai}) {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    return db.into(db.transaksi).insert(TransaksiCompanion.insert(
          id: id,
          tokoId: 't1',
          outletId: 'o1',
          penggunaId: 'u1',
          nomorStruk: 'STR-$id',
          tanggal: now,
          status: status,
          createdAt: now,
          updatedAt: now,
        ));
  }

  test('hitungan belum-sync mengikuti basis data: naik saat transaksi offline masuk, turun saat ditandai terkirim',
      () async {
    final nilai = <int>[];
    final langganan = db.transaksiDao.watchJumlahBelumSync().listen(nilai.add);
    addTearDown(langganan.cancel);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(nilai.last, 0);

    await catat('a');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(nilai.last, 1, reason: 'transaksi offline pertama harus langsung terhitung');

    await catat('b');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(nilai.last, 2);

    await db.transaksiDao.tandaiSudahSync(['a', 'b'], DateTime.now().toUtc().millisecondsSinceEpoch);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(nilai.last, 0, reason: 'setelah sinkron hitungan kembali nol');
  });

  test('pesanan tersimpan dan draft tidak dihitung sebagai menunggu sync', () async {
    await catat('t', status: TransaksiStatus.tersimpan);
    await catat('d', status: TransaksiStatus.draft);
    expect(await db.transaksiDao.watchJumlahBelumSync().first, 0);
  });
}
