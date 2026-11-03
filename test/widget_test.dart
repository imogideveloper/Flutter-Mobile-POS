import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/features/produk/data/local/tables/produk_table.dart';

void main() {
  test('ProdukDao bisa insert dan membaca kembali produk aktif', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await db.produkDao.upsertProduk(ProdukCompanion.insert(
      id: 'p1',
      tokoId: 't1',
      nama: 'Kopi Hitam',
      tipe: ProdukTipe.barang,
      hargaJual: const Value(15000),
      createdAt: 0,
      updatedAt: 0,
    ));

    final aktif = await db.produkDao.watchProdukAktif().first;

    expect(aktif, hasLength(1));
    expect(aktif.single.nama, 'Kopi Hitam');
    expect(aktif.single.hargaJual, 15000);
  });
}
