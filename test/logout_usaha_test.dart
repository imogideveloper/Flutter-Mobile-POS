import 'package:apps_pos/core/auth/logout_usaha.dart';
import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/features/produk/data/local/tables/produk_table.dart';
import 'package:apps_pos/features/transaksi/data/local/tables/transaksi_table.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> tambahTransaksi({int? disinkronPada}) {
    return db.into(db.transaksi).insert(TransaksiCompanion.insert(
          id: 't-1',
          tokoId: 'toko-default',
          outletId: 'outlet-default',
          penggunaId: 'pengguna-default',
          nomorStruk: 'OUT1-1',
          tanggal: 1,
          status: TransaksiStatus.selesai,
          total: const Value(15000),
          totalBayar: const Value(15000),
          disinkronPada: Value(disinkronPada),
          createdAt: 1,
          updatedAt: 1,
        ));
  }

  test('tanpa data: belum-tersinkron = 0', () async {
    expect(await hitungBelumTersinkron(db), 0);
  });

  test('transaksi belum terkirim dihitung sebagai belum tersinkron', () async {
    await tambahTransaksi();
    expect(await hitungBelumTersinkron(db), 1);
  });

  test('transaksi yang sudah terkirim tidak menahan logout', () async {
    await tambahTransaksi(disinkronPada: 5);
    expect(await hitungBelumTersinkron(db), 0);
  });

  test('hapusSemuaDataLokal mengosongkan tabel bisnis dan tetap bisa dipakai lagi', () async {
    await tambahTransaksi(disinkronPada: 5);
    await db.produkDao.upsertProduk(ProdukCompanion.insert(
      id: 'p1',
      tokoId: 'toko-default',
      nama: 'Kopi',
      tipe: ProdukTipe.barang,
      createdAt: 0,
      updatedAt: 0,
    ));
    expect((await db.select(db.transaksi).get()), isNotEmpty);

    await db.hapusSemuaDataLokal();

    expect(await db.select(db.transaksi).get(), isEmpty);
    expect(await db.select(db.produk).get(), isEmpty);

    // FK kembali aktif dan DB tetap bisa ditulis (pairing/seed berikutnya).
    await db.produkDao.upsertProduk(ProdukCompanion.insert(
      id: 'p2',
      tokoId: 'toko-baru',
      nama: 'Teh',
      tipe: ProdukTipe.barang,
      createdAt: 0,
      updatedAt: 0,
    ));
    expect(await db.select(db.produk).get(), hasLength(1));
  });
}
