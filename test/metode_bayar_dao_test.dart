import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/features/transaksi/data/local/tables/metode_bayar_table.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// BUG-011 (uji manual 2026-11-08): mengubah aktif/nonaktif metode bayar
/// selalu gagal di HP karena penyimpanan lokal memakai INSERT parsial yang
/// ditolak SQLite (NOT NULL). Metode update-only ini harus berhasil.
void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.into(db.metodeBayar).insert(
          MetodeBayarCompanion.insert(
            id: 'mb-tunai',
            tokoId: 'toko-1',
            nama: 'Tunai',
            tipe: MetodeBayarTipe.tunai,
            createdAt: 1000,
            updatedAt: 1000,
          ),
        );
  });

  tearDown(() => db.close());

  test('upsert parsial (id + aktif saja) memang ditolak - penyebab BUG-011', () async {
    await expectLater(
      db.metodeBayarDao.upsertMetodeBayar(
        const MetodeBayarCompanion(id: Value('mb-tunai'), aktif: Value(false)),
      ),
      throwsA(anything),
    );
  });

  test('ubahAktif menonaktifkan lalu mengaktifkan kembali tanpa mengubah kolom lain', () async {
    await db.metodeBayarDao.ubahAktif('mb-tunai', false, now: 2000);
    var row = await (db.select(db.metodeBayar)..where((t) => t.id.equals('mb-tunai'))).getSingle();
    expect(row.aktif, isFalse);
    expect(row.nama, 'Tunai');
    expect(row.tokoId, 'toko-1');
    expect(row.updatedAt, 2000);

    await db.metodeBayarDao.ubahAktif('mb-tunai', true, now: 3000);
    row = await (db.select(db.metodeBayar)..where((t) => t.id.equals('mb-tunai'))).getSingle();
    expect(row.aktif, isTrue);
  });

  test('ubahNamaUrutan hanya mengubah nama dan urutan', () async {
    await db.metodeBayarDao.ubahNamaUrutan('mb-tunai', nama: 'Cash', urutan: 3, now: 2000);
    final row = await (db.select(db.metodeBayar)..where((t) => t.id.equals('mb-tunai'))).getSingle();
    expect(row.nama, 'Cash');
    expect(row.urutan, 3);
    expect(row.tipe, MetodeBayarTipe.tunai);
    expect(row.aktif, isTrue);
  });

  test('idMetodeTunai mengembalikan ID metode tunai toko, atau null bila tidak ada', () async {
    expect(await db.metodeBayarDao.idMetodeTunai('toko-1'), 'mb-tunai');
    expect(await db.metodeBayarDao.idMetodeTunai('toko-lain'), isNull);
  });
}
