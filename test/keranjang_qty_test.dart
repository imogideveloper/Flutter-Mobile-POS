import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/core/harga/kalkulator.dart' as k;
import 'package:apps_pos/features/produk/data/local/tables/produk_table.dart' show ProdukTipe;
import 'package:apps_pos/features/produk/domain/produk.dart';
import 'package:apps_pos/features/transaksi/data/transaksi_repository.dart';
import 'package:apps_pos/features/transaksi/domain/item_keranjang.dart';
import 'package:apps_pos/features/transaksi/presentation/providers/keranjang_provider.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Kontrol jumlah di keranjang (FEAT-058, BUG-021, TASK-114): qty tidak pernah
/// negatif, item yang dihapus tidak ikut tersimpan, total selalu konsisten.
void main() {
  const kopi = Produk(
    id: 'p-kopi',
    tokoId: 't1',
    nama: 'Kopi',
    tipe: ProdukTipe.barang,
    lacakStok: false,
    punyaVarian: false,
    pakaiResep: false,
    hpp: 8000,
    hargaJual: 18000,
    dijual: true,
    aktif: true,
  );
  const roti = Produk(
    id: 'p-roti',
    tokoId: 't1',
    nama: 'Roti',
    tipe: ProdukTipe.barang,
    lacakStok: false,
    punyaVarian: false,
    pakaiResep: false,
    hpp: 5000,
    hargaJual: 12000,
    dijual: true,
    aktif: true,
  );
  const large = ModifierPilihan(modifierId: 'm-large', nama: 'Large', harga: 5000);

  ProviderContainer buat() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  group('qty di keranjang', () {
    test('qty 0 atau negatif menghapus baris; tidak pernah ada baris dengan qty <= 0', () {
      final c = buat();
      final n = c.read(keranjangProvider.notifier);
      n.tambah(kopi);
      n.tambah(roti);

      n.ubahQty('p-kopi', 0);
      expect(c.read(keranjangProvider).map((i) => i.produkId), ['p-roti']);

      n.ubahQty('p-roti', -3);
      expect(c.read(keranjangProvider), isEmpty);
    });

    test('mengurangi satu per satu sampai habis menghapus baris', () {
      final c = buat();
      final n = c.read(keranjangProvider.notifier);
      n.tambah(kopi);
      n.tambah(kopi);
      expect(c.read(keranjangProvider).single.qty, 2);

      n.ubahQty('p-kopi', 1);
      expect(c.read(keranjangProvider).single.qty, 1);
      n.ubahQty('p-kopi', 0);
      expect(c.read(keranjangProvider), isEmpty);
    });

    test('produk yang sama ditambah berulang menjadi satu baris dengan qty bertambah, bukan duplikat', () {
      final c = buat();
      final n = c.read(keranjangProvider.notifier);
      for (var i = 0; i < 5; i++) {
        n.tambah(kopi);
      }
      final baris = c.read(keranjangProvider);
      expect(baris, hasLength(1));
      expect(baris.single.qty, 5);
    });

    test('mengubah qty satu produk tidak mengubah produk lain', () {
      final c = buat();
      final n = c.read(keranjangProvider.notifier);
      n.tambah(kopi);
      n.tambah(roti);
      n.ubahQty('p-kopi', 7);
      final peta = {for (final i in c.read(keranjangProvider)) i.produkId: i.qty};
      expect(peta, {'p-kopi': 7, 'p-roti': 1});
    });

    test('subtotal mengikuti qty setiap kali diubah', () {
      final c = buat();
      final n = c.read(keranjangProvider.notifier);
      n.tambah(kopi); // 18.000
      n.tambah(roti); // 12.000
      expect(c.read(subtotalKeranjangProvider), 30000);

      n.ubahQty('p-kopi', 3); // 54.000 + 12.000
      expect(c.read(subtotalKeranjangProvider), 66000);

      n.hapus('p-roti');
      expect(c.read(subtotalKeranjangProvider), 54000);

      n.ubahQty('p-kopi', 0);
      expect(c.read(subtotalKeranjangProvider), 0);
    });

    test('dengan tambahan: subtotal = (harga + tambahan) x qty dan ikut berubah saat qty diubah', () {
      final c = buat();
      final n = c.read(keranjangProvider.notifier);
      n.tambah(kopi, modifiers: const [large]); // 23.000
      final kunci = c.read(keranjangProvider).single.kunciBaris;
      expect(c.read(subtotalKeranjangProvider), 23000);

      n.ubahQty(kunci, 4);
      expect(c.read(subtotalKeranjangProvider), 92000);
      expect(c.read(keranjangProvider).single.hargaSatuan, 18000, reason: 'harga dasar tidak berubah');

      n.ubahQty(kunci, 0);
      expect(c.read(keranjangProvider), isEmpty);
    });

    test('qty pecahan (mis. 0,5 kg) tetap dihitung benar dan tidak dibulatkan ke nol', () {
      final c = buat();
      final n = c.read(keranjangProvider.notifier);
      n.tambah(kopi);
      n.ubahQty('p-kopi', 0.5);
      expect(c.read(keranjangProvider).single.qty, 0.5);
      expect(c.read(subtotalKeranjangProvider), 9000);
    });
  });

  group('transaksi tersimpan', () {
    late AppDatabase db;
    late TransaksiRepository repo;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      repo = TransaksiRepository(db.transaksiDao, db.stokDao, db.produkDao);
    });
    tearDown(() => db.close());

    test('item yang dihapus dari keranjang tidak ikut tersimpan; total transaksi sesuai qty akhir', () async {
      final c = buat();
      final n = c.read(keranjangProvider.notifier);
      n.tambah(kopi);
      n.tambah(roti);
      n.ubahQty('p-kopi', 3);
      n.hapus('p-roti');
      final items = c.read(keranjangProvider);

      final hasil = k.hitung(k.TransaksiInput(items: [
        for (final i in items)
          k.ItemInput(
            produkId: i.produkId,
            varianId: null,
            namaProduk: i.namaProduk,
            qty: i.qty,
            hargaJual: i.hargaSatuan,
          ),
      ]));
      final trx = await repo.checkout(
        tokoId: 't1',
        outletId: 'o1',
        shiftId: 's1',
        penggunaId: 'u1',
        metodeBayarId: 'm1',
        items: items,
        hasil: hasil,
        totalBayar: 60000,
      );

      final tersimpan = await db.transaksiDao.itemUntukTransaksi(trx.id);
      expect(tersimpan.map((r) => (r.produkId, r.qty)), [('p-kopi', 3)]);
      final row = await db.transaksiDao.transaksiById(trx.id);
      expect(row.total, 54000);
      expect(row.subtotal, 54000);
    });
  });
}
