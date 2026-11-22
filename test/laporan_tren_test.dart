import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/core/harga/kalkulator.dart' as k;
import 'package:apps_pos/features/laporan/data/laporan_repository.dart';
import 'package:apps_pos/features/laporan/domain/ringkasan_laporan.dart';
import 'package:apps_pos/features/produk/data/local/tables/produk_table.dart';
import 'package:apps_pos/features/transaksi/data/transaksi_repository.dart';
import 'package:apps_pos/features/transaksi/domain/item_keranjang.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('hitungTren', () {
    test('perubahan persen, produk baru, dan produk yang hilang di periode ini', () {
      final hasil = hitungTren(
        {'Kopi': 150, 'Teh': 100, 'Roti': 40},
        {'Kopi': 100, 'Teh': 200, 'Susu': 50},
      );
      final per = {for (final t in hasil) t.nama: t};
      expect(per['Kopi']!.perubahanPersen, 50);
      expect(per['Teh']!.perubahanPersen, -50);
      expect(per['Roti']!.baru, isTrue);
      expect(per['Roti']!.perubahanPersen, isNull);
      expect(per['Susu']!.omzet, 0, reason: 'hanya terjual periode sebelumnya, tetap tampil sebagai turun 100%');
      expect(per['Susu']!.perubahanPersen, -100);
      expect(hasil.map((t) => t.nama).toList(), ['Kopi', 'Teh', 'Roti', 'Susu']);
    });

    test('dibatasi lima teratas dan mengabaikan omzet nol di kedua periode', () {
      final sekarang = {for (var i = 1; i <= 8; i++) 'P$i': i * 10, 'Nol': 0};
      expect(hitungTren(sekarang, const {}).length, 5);
      expect(hitungTren(sekarang, const {}).first.nama, 'P8');
      expect(hitungTren({'Nol': 0}, {'Nol': 0}), isEmpty);
    });
  });

  test('ringkasan memuat tren per produk dan per kategori terhadap periode sebelumnya', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = TransaksiRepository(db.transaksiDao, db.stokDao, db.produkDao);
    final laporan = LaporanRepository(db.transaksiDao);

    await db.produkDao.upsertKategori(KategoriCompanion.insert(
        id: 'k1', tokoId: 't1', nama: 'Minuman', createdAt: 0, updatedAt: 0));
    for (final (id, nama, kat) in [('p1', 'Kopi', 'k1'), ('p2', 'Roti', null)]) {
      await db.produkDao.upsertProduk(ProdukCompanion.insert(
        id: id,
        tokoId: 't1',
        kategoriId: Value(kat),
        nama: nama,
        tipe: ProdukTipe.barang,
        hargaJual: const Value(10000),
        createdAt: 0,
        updatedAt: 0,
      ));
    }

    Future<String> jual(String produkId, String nama, int qty) async {
      final items = [
        ItemKeranjang(produkId: produkId, namaProduk: nama, hargaSatuan: 10000, qty: qty.toDouble(), lacakStok: false),
      ];
      final hasil = k.hitung(k.TransaksiInput(items: [
        for (final i in items)
          k.ItemInput(produkId: i.produkId, varianId: null, namaProduk: i.namaProduk, qty: i.qty, hargaJual: i.hargaSatuan),
      ]));
      final id = await repo.checkout(
        tokoId: 't1',
        outletId: 'o1',
        shiftId: 's1',
        penggunaId: 'u1',
        metodeBayarId: 'metode-tunai-default',
        items: items,
        hasil: hasil,
        totalBayar: qty * 10000,
      );
      return id.id;
    }

    // Periode ini (hari ini): Kopi 3 porsi, Roti 1 porsi.
    await jual('p1', 'Kopi', 3);
    await jual('p2', 'Roti', 1);
    // Periode sebelumnya (kemarin): Kopi 2 porsi, Roti 4 porsi.
    final kemarin1 = await jual('p1', 'Kopi', 2);
    final kemarin2 = await jual('p2', 'Roti', 4);
    for (final id in [kemarin1, kemarin2]) {
      final t = await (db.select(db.transaksi)..where((x) => x.id.equals(id))).getSingle();
      await (db.update(db.transaksi)..where((x) => x.id.equals(id)))
          .write(TransaksiCompanion(tanggal: Value(t.tanggal - const Duration(days: 1).inMilliseconds)));
    }

    final r = await laporan.ringkasan('o1', PeriodeLaporan.hariIni);
    final produk = {for (final t in r.trenProduk) t.nama: t};
    expect(produk['Kopi']!.omzet, 30000);
    expect(produk['Kopi']!.omzetSebelumnya, 20000);
    expect(produk['Kopi']!.perubahanPersen, 50);
    expect(produk['Roti']!.perubahanPersen, -75);

    final kategori = {for (final t in r.trenKategori) t.nama: t};
    expect(kategori['Minuman']!.omzet, 30000);
    expect(kategori['Minuman']!.perubahanPersen, 50);
    expect(kategori['Tanpa kategori']!.omzetSebelumnya, 40000);
  });
}
