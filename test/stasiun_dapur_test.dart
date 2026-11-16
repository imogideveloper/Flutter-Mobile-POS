import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/core/struk/penyusun_struk.dart';
import 'package:apps_pos/core/struk/penyusun_tiket_dapur.dart';
import 'package:apps_pos/features/dapur/presentation/pages/stasiun_dapur_page.dart';
import 'package:apps_pos/features/dapur/presentation/tiket_dapur_helper.dart';
import 'package:apps_pos/features/produk/data/local/tables/produk_table.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

({String produkId, ItemTiketDapur item}) _i(String produkId, String nama) =>
    (produkId: produkId, item: ItemTiketDapur(namaProduk: nama, qty: 1));

void main() {
  group('tiket per stasiun (logika murni)', () {
    test('item dikelompokkan per stasiun mengikuti kemunculan pertama; tanpa stasiun = tiket umum', () {
      final hasil = kelompokkanPerStasiun(
        [_i('p1', 'Kopi'), _i('p2', 'Nasi Goreng'), _i('p3', 'Teh'), _i('p4', 'Air Mineral')],
        {'p1': 'Bar', 'p2': 'Dapur', 'p3': 'Bar'},
      );
      expect(hasil.map((t) => t.stasiun), ['Bar', 'Dapur', null]);
      expect(hasil[0].items.map((i) => i.namaProduk), ['Kopi', 'Teh']);
      expect(hasil[1].items.map((i) => i.namaProduk), ['Nasi Goreng']);
      expect(hasil[2].items.map((i) => i.namaProduk), ['Air Mineral']);
    });

    test('tanpa stasiun sama sekali tetap satu tiket umum, dan daftar kosong tanpa tiket', () {
      expect(kelompokkanPerStasiun([_i('p1', 'Kopi'), _i('p2', 'Teh')], const {}).length, 1);
      expect(kelompokkanPerStasiun(const [], const {'p1': 'Bar'}), isEmpty);
    });

    test('judul tiket memuat nama stasiun, bawaan tetap TIKET DAPUR', () {
      String judul(String? stasiun) => renderTeksStruk(
            susunTiketDapur(
              lebar: 32,
              data: TiketDapurData(
                nomorStruk: 'STR1',
                tanggalEpochMs: 1794300000000,
                namaStasiun: stasiun,
                items: const [ItemTiketDapur(namaProduk: 'Kopi', qty: 1)],
              ),
            ),
            32,
          ).first;
      expect(judul('Bar'), contains('TIKET BAR'));
      expect(judul(null), contains('TIKET DAPUR'));
      expect(judul('  '), contains('TIKET DAPUR'));
    });
  });

  test('DAO: stasiun per produk lewat kategori; dihapus, nonaktif, atau tanpa kategori = tiket umum', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    Future<void> stasiun(String id, String nama, {bool aktif = true, int? hapus}) =>
        db.produkDao.upsertStasiunDapur(StasiunDapurCompanion.insert(
          id: id,
          outletId: 'outlet-default',
          nama: nama,
          aktif: Value(aktif),
          createdAt: 0,
          updatedAt: 0,
          deletedAt: Value(hapus),
        ));
    Future<void> kat(String id, String? stasiunId) => db.produkDao.upsertKategori(KategoriCompanion.insert(
        id: id, tokoId: 'toko-default', nama: id, stasiunDapurId: Value(stasiunId), createdAt: 0, updatedAt: 0));
    Future<void> prod(String id, String? kategori) => db.produkDao.upsertProduk(ProdukCompanion.insert(
        id: id, tokoId: 'toko-default', kategoriId: Value(kategori), nama: id, tipe: ProdukTipe.barang, createdAt: 0, updatedAt: 0));

    await stasiun('s-bar', 'Bar');
    await stasiun('s-lama', 'Lama', hapus: 5);
    await stasiun('s-mati', 'Mati', aktif: false);
    await kat('k-bar', 's-bar');
    await kat('k-lama', 's-lama');
    await kat('k-mati', 's-mati');
    await kat('k-polos', null);
    await prod('kopi', 'k-bar');
    await prod('a', 'k-lama');
    await prod('b', 'k-mati');
    await prod('c', 'k-polos');
    await prod('d', null);

    expect(await db.produkDao.namaStasiunPerProduk(['kopi', 'a', 'b', 'c', 'd']), {'kopi': 'Bar'});
    expect(await db.produkDao.namaStasiunPerProduk(const []), isEmpty);
  });

  testWidgets('halaman stasiun menampilkan stasiun aktif saja', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.produkDao.upsertStasiunDapur(StasiunDapurCompanion.insert(
        id: 's1', outletId: 'outlet-default', nama: 'Bar', lebarKertasMm: const Value(80), createdAt: 0, updatedAt: 0));
    await db.produkDao.upsertStasiunDapur(StasiunDapurCompanion.insert(
        id: 's2', outletId: 'outlet-default', nama: 'Dihapus', createdAt: 0, updatedAt: 0, deletedAt: const Value(9)));

    await tester.pumpWidget(ProviderScope(
      overrides: overridesSudahLogin(db),
      child: const MaterialApp(home: StasiunDapurPage()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Bar'), findsOneWidget);
    expect(find.text('Kertas 80 mm'), findsOneWidget);
    expect(find.text('Dihapus'), findsNothing);

    await tester.tap(find.byKey(const Key('stasiun.tambah')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('stasiun.form.simpan')));
    await tester.pumpAndSettle();
    expect(find.text('Nama stasiun wajib diisi'), findsOneWidget, reason: 'nama kosong ditolak sebelum ke server');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
