import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/features/produk/data/local/tables/produk_table.dart' show ProdukTipe;
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Kategori bisa dikeluarkan dari tiket dapur (IMOGI no. 35).
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> kategori(String id, {required bool masuk}) => db.produkDao.upsertKategori(KategoriCompanion.insert(
        id: id,
        tokoId: 't1',
        nama: 'Kat $id',
        masukTiketDapur: Value(masuk),
        createdAt: 1,
        updatedAt: 1,
      ));

  Future<void> produk(String id, {String? kategoriId}) => db.produkDao.upsertProduk(ProdukCompanion.insert(
        id: id,
        tokoId: 't1',
        nama: 'Produk $id',
        tipe: ProdukTipe.barang,
        kategoriId: Value(kategoriId),
        createdAt: 1,
        updatedAt: 1,
      ));

  test('hanya produk dari kategori yang dimatikan yang dikecualikan; tanpa kategori selalu masuk', () async {
    await kategori('k-makan', masuk: true);
    await kategori('k-dingin', masuk: false);
    await produk('nasi', kategoriId: 'k-makan');
    await produk('es-teh', kategoriId: 'k-dingin');
    await produk('lepas');

    expect(await db.produkDao.produkTanpaTiketDapur(['nasi', 'es-teh', 'lepas']), {'es-teh'});
    expect(await db.produkDao.produkTanpaTiketDapur([]), isEmpty);
  });

  test('kategori baru bawaannya masuk tiket dapur', () async {
    await db.produkDao.upsertKategori(KategoriCompanion.insert(
      id: 'k1', tokoId: 't1', nama: 'Baru', createdAt: 1, updatedAt: 1,
    ));
    await produk('p1', kategoriId: 'k1');
    expect(await db.produkDao.produkTanpaTiketDapur(['p1']), isEmpty);
  });
}
