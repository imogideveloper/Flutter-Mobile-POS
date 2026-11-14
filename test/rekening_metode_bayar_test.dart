import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/features/transaksi/data/local/tables/metode_bayar_table.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rekening tujuan tersimpan pada metode transfer dan bisa dikosongkan', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.metodeBayarDao.upsertMetodeBayar(MetodeBayarCompanion.insert(
      id: 'm-tf',
      tokoId: 'toko-default',
      nama: 'Transfer',
      tipe: MetodeBayarTipe.transfer,
      createdAt: 0,
      updatedAt: 0,
    ));
    var baris = (await db.metodeBayarDao.watchSemuaMetodeBayar().first).single;
    expect(baris.rekeningNomor, isNull);

    await db.metodeBayarDao.ubahRekening('m-tf', bank: 'BCA', nomor: '123', nama: 'Kedai', now: 5);
    baris = (await db.metodeBayarDao.watchSemuaMetodeBayar().first).single;
    expect(baris.rekeningBank, 'BCA');
    expect(baris.rekeningNomor, '123');
    expect(baris.rekeningNama, 'Kedai');

    await db.metodeBayarDao.ubahRekening('m-tf', bank: null, nomor: null, nama: null, now: 6);
    baris = (await db.metodeBayarDao.watchSemuaMetodeBayar().first).single;
    expect(baris.rekeningNomor, isNull);
  });
}
