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

/// Varian dan tambahan produk (dokumen IMOGI no. 42): ukuran, level gula/pedas,
/// topping berbayar. Pilihan tersimpan di item, ikut harga, dan bertahan di
/// pesanan tersimpan, riwayat, dan struk.
void main() {
  const large = ModifierPilihan(modifierId: 'm-large', nama: 'Large', harga: 5000);
  const keju = ModifierPilihan(modifierId: 'm-keju', nama: 'Extra keju', harga: 3000);
  const kurangGula = ModifierPilihan(modifierId: 'm-gula', nama: 'Less sugar');

  const dasar = ItemKeranjang(produkId: 'p-1', namaProduk: 'Es Kopi', hargaSatuan: 18000, qty: 2, lacakStok: false);

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

  group('ItemKeranjang', () {
    test('tanpa tambahan: kunci baris = produkId dan harga tidak berubah (perilaku lama)', () {
      expect(dasar.kunciBaris, 'p-1');
      expect(dasar.hargaSatuanFinal, 18000);
      expect(dasar.subtotal, 36000);
    });

    test('tambahan berbayar menambah harga per unit dan subtotal', () {
      final i = ItemKeranjang(
        produkId: 'p-1',
        namaProduk: 'Es Kopi',
        hargaSatuan: 18000,
        qty: 2,
        lacakStok: false,
        modifiers: const [large, keju, kurangGula],
      );
      expect(i.tambahanModifier, 8000);
      expect(i.hargaSatuanFinal, 26000);
      expect(i.subtotal, 52000);
    });

    test('kunci baris tidak peduli urutan pilihan, dan berbeda bila pilihan berbeda', () {
      ItemKeranjang buat(List<ModifierPilihan> m) =>
          ItemKeranjang(produkId: 'p-1', namaProduk: 'x', hargaSatuan: 1, qty: 1, lacakStok: false, modifiers: m);
      expect(buat(const [large, keju]).kunciBaris, buat(const [keju, large]).kunciBaris);
      expect(buat(const [large]).kunciBaris, isNot(buat(const [keju]).kunciBaris));
      expect(buat(const [large]).kunciBaris, isNot('p-1'));
    });

    test('copyWith mempertahankan tambahan', () {
      final i = ItemKeranjang(
        produkId: 'p-1',
        namaProduk: 'x',
        hargaSatuan: 1,
        qty: 1,
        lacakStok: false,
        modifiers: const [large],
      ).copyWith(qty: 3);
      expect(i.qty, 3);
      expect(i.modifiers, [large]);
    });
  });

  group('keranjang', () {
    ProviderContainer buat() {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      return c;
    }

    test('produk sama dengan pilihan berbeda menjadi baris terpisah', () {
      final c = buat();
      final n = c.read(keranjangProvider.notifier);
      n.tambah(produk, modifiers: const [large]);
      n.tambah(produk, modifiers: const [keju]);
      n.tambah(produk);
      expect(c.read(keranjangProvider).length, 3);
    });

    test('pilihan yang sama menambah qty baris yang sama', () {
      final c = buat();
      final n = c.read(keranjangProvider.notifier);
      n.tambah(produk, modifiers: const [large, kurangGula]);
      n.tambah(produk, modifiers: const [kurangGula, large]);
      final baris = c.read(keranjangProvider);
      expect(baris.length, 1);
      expect(baris.single.qty, 2);
    });

    test('ubah qty dan hapus bekerja per baris, tidak mengganggu baris lain dari produk yang sama', () {
      final c = buat();
      final n = c.read(keranjangProvider.notifier);
      n.tambah(produk, modifiers: const [large]);
      n.tambah(produk);
      final kunciLarge = c.read(keranjangProvider).first.kunciBaris;

      n.ubahQty(kunciLarge, 4);
      expect(c.read(keranjangProvider).first.qty, 4);
      expect(c.read(keranjangProvider).last.qty, 1);

      n.hapus(kunciLarge);
      final sisa = c.read(keranjangProvider);
      expect(sisa.length, 1);
      expect(sisa.single.modifiers, isEmpty);
    });

    test('subtotal keranjang menghitung tambahan', () {
      final c = buat();
      final n = c.read(keranjangProvider.notifier);
      n.tambah(produk, modifiers: const [large]);
      expect(c.read(subtotalKeranjangProvider), 23000);
    });
  });

  group('kalkulator harga', () {
    test('tambahan ikut harga satuan akhir', () {
      final hasil = k.hitung(k.TransaksiInput(items: [
        k.ItemInput(
          produkId: 'p-1',
          varianId: null,
          namaProduk: 'Es Kopi',
          qty: 2,
          hargaJual: 18000,
          modifiers: [k.ModifierInput(nama: 'Large', harga: 5000), k.ModifierInput(nama: 'Extra keju', harga: 3000)],
        ),
      ]));
      expect(hasil.items.single.hargaSatuan, 26000);
      expect(hasil.items.single.subtotal, 52000);
      expect(hasil.subtotal, 52000);
    });
  });

  group('penyimpanan', () {
    late AppDatabase db;
    late TransaksiRepository repo;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      repo = TransaksiRepository(db.transaksiDao, db.stokDao, db.produkDao);
    });

    tearDown(() => db.close());

    const items = [
      ItemKeranjang(
        produkId: 'p-1',
        namaProduk: 'Es Kopi',
        hargaSatuan: 18000,
        qty: 2,
        lacakStok: false,
        modifiers: [large, kurangGula],
      ),
      ItemKeranjang(produkId: 'p-2', namaProduk: 'Roti', hargaSatuan: 12000, qty: 1, lacakStok: false),
    ];

    k.HasilKalkulasi hitung() => k.hitung(k.TransaksiInput(items: [
          k.ItemInput(
            produkId: 'p-1',
            varianId: null,
            namaProduk: 'Es Kopi',
            qty: 2,
            hargaJual: 18000,
            modifiers: [k.ModifierInput(nama: 'Large', harga: 5000), k.ModifierInput(nama: 'Less sugar', harga: 0)],
          ),
          k.ItemInput(produkId: 'p-2', varianId: null, namaProduk: 'Roti', qty: 1, hargaJual: 12000),
        ]));

    test('checkout menyimpan tambahan per item dan harga akhir sudah termasuk tambahan', () async {
      final hasil = await repo.checkout(
        tokoId: 't1',
        outletId: 'o1',
        shiftId: 's1',
        penggunaId: 'u1',
        metodeBayarId: 'm1',
        items: items,
        hasil: hitung(),
        totalBayar: 60000,
      );
      final itemRows = await db.transaksiDao.itemUntukTransaksi(hasil.id);
      final kopi = itemRows.firstWhere((r) => r.produkId == 'p-1');
      final roti = itemRows.firstWhere((r) => r.produkId == 'p-2');
      expect(kopi.hargaSatuan, 23000, reason: '18000 + Large 5000 + Less sugar 0');
      expect(roti.hargaSatuan, 12000);

      final mod = await db.transaksiDao.modifierUntukItemList([for (final r in itemRows) r.id]);
      expect(mod.map((m) => m.nama).toSet(), {'Large', 'Less sugar'});
      expect(mod.every((m) => m.itemTransaksiId == kopi.id), isTrue, reason: 'roti tidak punya tambahan');
      expect(mod.firstWhere((m) => m.nama == 'Large').harga, 5000);
      expect(mod.firstWhere((m) => m.nama == 'Large').modifierId, 'm-large');
    });

    test('riwayat (detail) menampilkan tambahan dan harga dasar tanpa menghitung dua kali', () async {
      final hasil = await repo.checkout(
        tokoId: 't1',
        outletId: 'o1',
        shiftId: 's1',
        penggunaId: 'u1',
        metodeBayarId: 'm1',
        items: items,
        hasil: hitung(),
        totalBayar: 60000,
      );
      final detail = await repo.detailTransaksi(hasil.id);
      final kopi = detail.items.firstWhere((i) => i.produkId == 'p-1');
      expect(kopi.modifiers.map((m) => m.nama), ['Large', 'Less sugar']);
      expect(kopi.hargaSatuan, 18000, reason: 'harga dasar = tersimpan dikurangi tambahan');
      expect(kopi.hargaSatuanFinal, 23000);
      expect(kopi.subtotal, 46000);
      expect(detail.items.firstWhere((i) => i.produkId == 'p-2').modifiers, isEmpty);
    });

    test('pesanan tersimpan menyimpan tambahan dan memulihkannya saat dibuka lagi', () async {
      final draftId = await repo.simpanPesanan(
        tokoId: 't1',
        outletId: 'o1',
        penggunaId: 'u1',
        items: items,
        hasil: hitung(),
      );
      final pulih = await repo.itemUntukResumePesanan(draftId);
      final kopi = pulih.firstWhere((i) => i.produkId == 'p-1');
      expect(kopi.modifiers.map((m) => m.nama), ['Large', 'Less sugar']);
      expect(kopi.hargaSatuan, 18000, reason: 'tidak boleh 23000 (tambahan terhitung dua kali)');
      expect(kopi.kunciBaris, items.first.kunciBaris);
    });

    test('menghapus pesanan tersimpan ikut menghapus baris tambahannya', () async {
      final draftId = await repo.simpanPesanan(
        tokoId: 't1',
        outletId: 'o1',
        penggunaId: 'u1',
        items: items,
        hasil: hitung(),
      );
      expect(await db.select(db.itemTransaksiModifier).get(), isNotEmpty);
      await db.transaksiDao.hapusPesananTersimpan(draftId);
      expect(await db.select(db.itemTransaksiModifier).get(), isEmpty);
      expect(await db.select(db.itemTransaksi).get(), isEmpty);
    });
  });
}
