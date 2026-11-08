import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/features/produk/data/local/tables/produk_table.dart' show ProdukTipe;
import 'package:apps_pos/features/produk/domain/grup_tambahan.dart';
import 'package:apps_pos/features/produk/domain/produk.dart';
import 'package:apps_pos/features/transaksi/domain/item_keranjang.dart';
import 'package:apps_pos/features/transaksi/presentation/widgets/pilih_tambahan_sheet.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Katalog varian/tambahan (IMOGI no. 42): penyimpanan lokal hasil pull,
/// aturan pilih, dan pemilih di kasir.
void main() {
  const ukuran = GrupTambahan(
    id: 'g-ukuran',
    nama: 'Ukuran',
    minPilih: 1,
    maksPilih: 1,
    opsi: [
      OpsiTambahan(id: 'm-reg', nama: 'Regular', harga: 0),
      OpsiTambahan(id: 'm-large', nama: 'Large', harga: 5000),
    ],
  );
  const topping = GrupTambahan(
    id: 'g-topping',
    nama: 'Topping',
    minPilih: 0,
    maksPilih: 2,
    opsi: [
      OpsiTambahan(id: 'm-keju', nama: 'Keju', harga: 3000),
      OpsiTambahan(id: 'm-boba', nama: 'Boba', harga: 4000),
      OpsiTambahan(id: 'm-jelly', nama: 'Jelly', harga: 2000),
    ],
  );

  group('aturan pilih', () {
    test('grup wajib pilih satu menolak kosong dan menerima satu', () {
      expect(ukuran.wajib, isTrue);
      expect(ukuran.validasi(0), isNotNull);
      expect(ukuran.validasi(1), isNull);
      expect(ukuran.validasi(2), isNotNull);
    });

    test('grup opsional dengan maksimal', () {
      expect(topping.wajib, isFalse);
      expect(topping.validasi(0), isNull);
      expect(topping.validasi(2), isNull);
      expect(topping.validasi(3), isNotNull);
    });
  });

  group('penyimpanan lokal', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    Future<void> isiProduk(String id) => db.produkDao.upsertProduk(ProdukCompanion.insert(
          id: id,
          tokoId: 't1',
          nama: 'Produk $id',
          tipe: ProdukTipe.barang,
          createdAt: 1,
          updatedAt: 1,
        ));

    Future<void> isiGrup({bool opsiNonaktif = false, bool grupDihapus = false}) async {
      await db.produkDao.upsertGrupModifier(GrupModifierCompanion.insert(
        id: 'g1',
        tokoId: 't1',
        nama: 'Ukuran',
        minPilih: const Value(1),
        maksPilih: const Value(1),
        createdAt: 1,
        updatedAt: 1,
        deletedAt: Value(grupDihapus ? 5 : null),
      ));
      await db.produkDao.upsertModifier(ModifierCompanion.insert(
        id: 'm1', grupModifierId: 'g1', nama: 'Large', hargaTambahan: const Value(5000), createdAt: 1, updatedAt: 1,
      ));
      await db.produkDao.upsertModifier(ModifierCompanion.insert(
        id: 'm2',
        grupModifierId: 'g1',
        nama: 'Jumbo',
        aktif: Value(!opsiNonaktif),
        urutan: const Value(1),
        createdAt: 1,
        updatedAt: 1,
      ));
    }

    test('grup dan opsi tampil untuk produk yang ditautkan, lengkap dengan aturan dan harga', () async {
      await isiProduk('p1');
      await isiProduk('p2');
      await isiGrup();
      await db.produkDao.gantiRelasiProdukGrup([('p1', 'g1')]);

      final grup = await db.produkDao.grupUntukProduk('p1');
      expect(grup.single.nama, 'Ukuran');
      expect((grup.single.minPilih, grup.single.maksPilih), (1, 1));
      expect(grup.single.opsi.map((o) => (o.nama, o.harga)), [('Large', 5000), ('Jumbo', 0)]);
      expect(await db.produkDao.grupUntukProduk('p2'), isEmpty);
    });

    test('opsi nonaktif dan grup terhapus tidak muncul di kasir', () async {
      await isiProduk('p1');
      await isiGrup(opsiNonaktif: true);
      await db.produkDao.gantiRelasiProdukGrup([('p1', 'g1')]);
      expect((await db.produkDao.grupUntukProduk('p1')).single.opsi.map((o) => o.nama), ['Large']);

      await db.produkDao.hapusGrupLokal('g1');
      expect(await db.produkDao.grupUntukProduk('p1'), isEmpty);
    });

    test('relasi diganti seluruhnya oleh snapshot terbaru', () async {
      await isiProduk('p1');
      await isiProduk('p2');
      await isiGrup();
      await db.produkDao.gantiRelasiProdukGrup([('p1', 'g1')]);
      await db.produkDao.gantiRelasiProdukGrup([('p2', 'g1')]);
      expect(await db.produkDao.grupUntukProduk('p1'), isEmpty);
      expect(await db.produkDao.grupUntukProduk('p2'), isNotEmpty);
      expect(await db.produkDao.produkIdUntukGrup('g1'), {'p2'});
    });

    test('halaman kelola melihat semua opsi termasuk nonaktif', () async {
      await isiGrup(opsiNonaktif: true);
      final semua = await db.produkDao.watchGrupKelola().first;
      expect(semua.single.opsi.map((o) => (o.nama, o.aktif)), [('Large', true), ('Jumbo', false)]);
    });
  });

  group('pemilih di kasir', () {
    const produk = Produk(
      id: 'p-1',
      tokoId: 't1',
      nama: 'Es Kopi',
      tipe: ProdukTipe.barang,
      lacakStok: false,
      punyaVarian: false,
      pakaiResep: false,
      hpp: 8000,
      hargaJual: 18000,
      dijual: true,
      aktif: true,
    );

    Future<Future<List<ModifierPilihan>?> Function()> buka(WidgetTester tester, {required List<GrupTambahan> grup}) async {
      List<ModifierPilihan>? hasil;
      var selesai = false;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            key: const Key('buka'),
            onPressed: () async {
              hasil = await tampilkanPilihTambahan(context, produk: produk, grup: grup);
              selesai = true;
            },
            child: const Text('buka'),
          ),
        ),
      ));
      return () async {
        expect(selesai, isTrue);
        return hasil;
      };
    }

    testWidgets('grup wajib belum dipilih: ditolak dengan pesan, lalu lolos setelah memilih', (tester) async {
      final hasil = await buka(tester, grup: const [ukuran, topping]);
      await tester.pump();
      await tester.tap(find.byKey(const Key('buka')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('tambahan.simpan')));
      await tester.pump();
      expect(find.byKey(const Key('tambahan.galat')), findsOneWidget);
      expect(find.text('Pilih salah satu Ukuran'), findsOneWidget);

      await tester.tap(find.byKey(const Key('tambahan.opsi.m-large')));
      await tester.pump();
      expect(find.textContaining('23.000'), findsOneWidget, reason: '18.000 + Large 5.000');

      await tester.tap(find.byKey(const Key('tambahan.simpan')));
      await tester.pumpAndSettle();
      final pilihan = await hasil();
      expect(pilihan!.map((m) => m.nama), ['Large']);
      expect(pilihan.single.harga, 5000);
      expect(pilihan.single.modifierId, 'm-large');
    });

    testWidgets('pilih-tunggal berpindah pilihan; topping dibatasi maksimal', (tester) async {
      final hasil = await buka(tester, grup: const [ukuran, topping]);
      await tester.pump();
      await tester.tap(find.byKey(const Key('buka')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('tambahan.opsi.m-reg')));
      await tester.tap(find.byKey(const Key('tambahan.opsi.m-large')));
      await tester.tap(find.byKey(const Key('tambahan.opsi.m-keju')));
      await tester.tap(find.byKey(const Key('tambahan.opsi.m-boba')));
      await tester.tap(find.byKey(const Key('tambahan.opsi.m-jelly'))); // melebihi maks 2: diabaikan
      await tester.pump();

      await tester.tap(find.byKey(const Key('tambahan.simpan')));
      await tester.pumpAndSettle();
      final pilihan = (await hasil())!;
      expect(pilihan.map((m) => m.nama).toSet(), {'Large', 'Keju', 'Boba'});
    });

    testWidgets('ditutup tanpa memilih mengembalikan null (tidak menambah apa pun)', (tester) async {
      final hasil = await buka(tester, grup: const [ukuran]);
      await tester.pump();
      await tester.tap(find.byKey(const Key('buka')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('tambahan.tutup')));
      await tester.pumpAndSettle();
      expect(await hasil(), isNull);
    });
  });
}
