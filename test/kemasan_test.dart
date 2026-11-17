import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/core/harga/kalkulator.dart' as k;
import 'package:apps_pos/features/produk/data/local/tables/produk_table.dart' show ProdukTipe;
import 'package:apps_pos/features/produk/domain/produk.dart';
import 'package:apps_pos/features/stok/data/local/tables/mutasi_stok_table.dart' show MutasiJenis;
import 'package:apps_pos/features/transaksi/data/transaksi_repository.dart';
import 'package:apps_pos/features/transaksi/domain/item_keranjang.dart';
import 'package:apps_pos/features/transaksi/presentation/providers/keranjang_provider.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:apps_pos/features/transaksi/presentation/widgets/pilih_kemasan_sheet.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _dus = KemasanPilihan(nama: 'Dus', isi: 12, harga: 150000);

Produk _aqua() => const Produk(
      id: 'aqua',
      tokoId: 't1',
      nama: 'Aqua',
      tipe: ProdukTipe.barang,
      hargaJual: 15000,
      hpp: 10000,
      lacakStok: true,
      punyaVarian: false,
      pakaiResep: false,
      dijual: true,
      aktif: true,
    );

void main() {
  group('keranjang (jual per kemasan)', () {
    test('kemasan = baris terpisah dari satuan dasar: harga kemasan, nama berlabel, isi tersimpan', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(keranjangProvider.notifier);
      n.tambah(_aqua());
      n.tambah(_aqua(), kemasan: _dus);
      n.tambah(_aqua(), kemasan: _dus); // kemasan yang sama menambah qty barisnya

      final baris = c.read(keranjangProvider);
      expect(baris.length, 2);
      final dasar = baris.firstWhere((i) => !i.kemasan);
      final dus = baris.firstWhere((i) => i.kemasan);
      expect(dasar.hargaSatuan, 15000);
      expect(dasar.qtyDasar, 1);
      expect(dus.namaProduk, 'Aqua (Dus)');
      expect(dus.hargaSatuan, 150000);
      expect(dus.qty, 2);
      expect(dus.qtyDasar, 24, reason: 'stok berkurang qty x isi');
      expect(dus.subtotal, 300000);
      expect(dus.kunciBaris, isNot(dasar.kunciBaris));
    });

    test('diskon dan ubah qty mempertahankan isi kemasan', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(keranjangProvider.notifier);
      n.tambah(_aqua(), kemasan: _dus);
      final kunci = c.read(keranjangProvider).single.kunciBaris;
      n.ubahQty(kunci, 3);
      n.aturDiskon(kunci, persen: 10, disetujuiOleh: 'u1');
      final item = c.read(keranjangProvider).single;
      expect(item.isiKemasan, 12);
      expect(item.namaKemasan, 'Dus');
      expect(item.qtyDasar, 36);
    });
  });

  group('checkout dan void per kemasan (lokal)', () {
    late AppDatabase db;
    late TransaksiRepository repo;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      repo = TransaksiRepository(db.transaksiDao, db.stokDao, db.produkDao);
      await db.produkDao.upsertProduk(ProdukCompanion.insert(
        id: 'aqua',
        tokoId: 't1',
        nama: 'Aqua',
        tipe: ProdukTipe.barang,
        hargaJual: const Value(15000),
        hpp: const Value(10000),
        createdAt: 0,
        updatedAt: 0,
      ));
      await db.stokDao.catatMutasi(
        tokoId: 't1',
        outletId: 'o1',
        produkId: 'aqua',
        jenis: MutasiJenis.stokAwal,
        qty: 100,
        refTipe: 'uji',
        refId: 'awal',
        dibuatOleh: 'u1',
      );
    });

    tearDown(() => db.close());

    Future<double> stok() async =>
        (await db.stokDao.cariStok(outletId: 'o1', produkId: 'aqua'))!.jumlah;

    test('checkout memotong stok qty x isi, menyimpan isi/nama kemasan dan HPP per kemasan; void mengembalikan', () async {
      final item = ItemKeranjang(
        produkId: 'aqua',
        namaProduk: 'Aqua (Dus)',
        hargaSatuan: 150000,
        qty: 2,
        lacakStok: true,
        isiKemasan: 12,
        namaKemasan: 'Dus',
      );
      final hasil = k.hitung(k.TransaksiInput(items: [
        k.ItemInput(produkId: 'aqua', varianId: null, namaProduk: item.namaProduk, qty: item.qty, hargaJual: item.hargaSatuan),
      ]));
      final trx = await repo.checkout(
        tokoId: 't1',
        outletId: 'o1',
        shiftId: 's1',
        penggunaId: 'u1',
        metodeBayarId: 'metode-tunai-default',
        items: [item],
        hasil: hasil,
        totalBayar: 300000,
      );

      expect(await stok(), 100 - 24);
      final row = (await db.select(db.itemTransaksi).get()).single;
      expect(row.qty, 2);
      expect(row.hargaSatuan, 150000);
      expect(row.isiKemasan, 12);
      expect(row.namaKemasan, 'Dus');
      expect(row.hppSatuan, 120000, reason: 'HPP satuan dasar 10000 x isi 12');
      expect(trx.total, 300000);

      await repo.voidTransaksi(
        transaksiId: trx.id,
        tokoId: 't1',
        outletId: 'o1',
        alasan: 'salah',
        disetujuiOleh: 'u1',
        items: trx.items,
      );
      expect(await stok(), 100);
    });

    test('item biasa tetap isi 1 tanpa nama kemasan', () async {
      final item = ItemKeranjang(produkId: 'aqua', namaProduk: 'Aqua', hargaSatuan: 15000, qty: 2, lacakStok: true);
      final hasil = k.hitung(k.TransaksiInput(items: [
        k.ItemInput(produkId: 'aqua', varianId: null, namaProduk: 'Aqua', qty: 2, hargaJual: 15000),
      ]));
      await repo.checkout(
        tokoId: 't1',
        outletId: 'o1',
        shiftId: 's1',
        penggunaId: 'u1',
        metodeBayarId: 'metode-tunai-default',
        items: [item],
        hasil: hasil,
        totalBayar: 30000,
      );
      final row = (await db.select(db.itemTransaksi).get()).single;
      expect(row.isiKemasan, 1);
      expect(row.namaKemasan, isNull);
      expect(await stok(), 98);
    });

    test('DAO kemasan: aktif saja, urut isi, dikelompokkan per produk', () async {
      Future<void> kemasan(String id, double isi, {int? hapus}) => db.produkDao.upsertKemasan(
            ProdukKemasanCompanion.insert(
              id: id,
              tokoId: 't1',
              produkId: 'aqua',
              nama: id,
              isi: isi,
              harga: 1000,
              createdAt: 0,
              updatedAt: 0,
              deletedAt: Value(hapus),
            ),
          );
      await kemasan('Dus', 24);
      await kemasan('Pak', 6);
      await kemasan('Lama', 3, hapus: 9);

      final daftar = await db.produkDao.watchSemuaKemasan('t1').first;
      expect(daftar.map((e) => e.nama), ['Pak', 'Dus']);
      expect(await db.produkDao.watchSemuaKemasan('toko-lain').first, isEmpty);
    });
  });

  testWidgets('lembar pilih satuan: satuan dasar dan kemasan; hasil sesuai ketukan', (tester) async {
    PilihanSatuan? hasil;
    var selesai = false;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            key: const Key('buka'),
            onPressed: () async {
              hasil = await tampilkanPilihKemasan(context, produk: _aqua(), kemasan: const [_dus]);
              selesai = true;
            },
            child: const Text('buka'),
          ),
        ),
      ),
    ));

    await tester.tap(find.byKey(const Key('buka')));
    await tester.pumpAndSettle();
    expect(find.text('Rp15.000'), findsOneWidget, reason: 'harga satuan dasar');
    expect(find.text('Rp150.000'), findsOneWidget, reason: 'harga kemasan');
    expect(find.text('Isi 12 satuan'), findsOneWidget);

    await tester.tap(find.byKey(const Key('pilihKemasan.Dus')));
    await tester.pumpAndSettle();
    expect(selesai, isTrue);
    expect(hasil!.kemasan!.isi, 12);

    selesai = false;
    await tester.tap(find.byKey(const Key('buka')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pilihKemasan.dasar')));
    await tester.pumpAndSettle();
    expect(hasil!.kemasan, isNull, reason: 'satuan dasar = tanpa kemasan');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
