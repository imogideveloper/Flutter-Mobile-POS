import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/core/harga/kalkulator.dart' as k;
import 'package:apps_pos/features/produk/data/local/tables/produk_table.dart';
import 'package:apps_pos/features/promo/data/local/tables/pajak_table.dart'
    show PajakTipe;
import 'package:apps_pos/features/promo/data/local/tables/promo_table.dart'
    show PromoCakupan, PromoTipe;
import 'package:apps_pos/features/promo/domain/pajak.dart' as domain_pajak;
import 'package:apps_pos/features/promo/domain/promo.dart' as domain_promo;
import 'package:apps_pos/features/stok/data/local/tables/mutasi_stok_table.dart'
    show MutasiJenis;
import 'package:apps_pos/features/transaksi/data/local/tables/transaksi_table.dart'
    show TransaksiStatus;
import 'package:apps_pos/features/transaksi/data/transaksi_repository.dart';
import 'package:apps_pos/features/transaksi/domain/item_keranjang.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Membangun HasilKalkulasi via mesin yg SAMA dgn produksi
/// (lib/core/harga/kalkulator.dart), dari daftar ItemKeranjang - meniru
/// apa yg hasilHargaKeranjangProvider lakukan di app sungguhan, supaya
/// tes ini tetap memakai satu mesin hitung yg sama (tahap 3a bagian A).
k.HasilKalkulasi _hitung(
  List<ItemKeranjang> items, {
  List<k.PajakInput> pajakDefault = const [],
}) {
  return k.hitung(
    k.TransaksiInput(
      items: [
        for (final item in items)
          k.ItemInput(
            produkId: item.produkId,
            varianId: null,
            namaProduk: item.namaProduk,
            qty: item.qty,
            hargaJual: item.hargaSatuan,
          ),
      ],
      pajakDefault: pajakDefault,
    ),
  );
}

void main() {
  late AppDatabase db;
  late TransaksiRepository repo;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = TransaksiRepository(db.transaksiDao, db.stokDao, db.produkDao);

    await db.produkDao.upsertProduk(
      ProdukCompanion.insert(
        id: 'p-barang',
        tokoId: 't1',
        nama: 'Kopi Hitam',
        tipe: ProdukTipe.barang,
        hargaJual: const Value(15000),
        createdAt: 0,
        updatedAt: 0,
      ),
    );
    await db.produkDao.upsertProduk(
      ProdukCompanion.insert(
        id: 'p-jasa',
        tokoId: 't1',
        nama: 'Jasa Antar',
        tipe: ProdukTipe.jasa,
        hargaJual: const Value(5000),
        lacakStok: const Value(false),
        createdAt: 0,
        updatedAt: 0,
      ),
    );

    // Saldo awal stok barang = 10, lewat jalur yang sudah ada (catatMutasi).
    await db.stokDao.catatMutasi(
      tokoId: 't1',
      outletId: 'o1',
      produkId: 'p-barang',
      jenis: MutasiJenis.stokAwal,
      qty: 10,
    );
  });

  tearDown(() => db.close());

  test(
    'checkout menyimpan transaksi+item+pembayaran dan mendebet stok item yang lacakStok',
    () async {
      final items = const [
        ItemKeranjang(
          produkId: 'p-barang',
          namaProduk: 'Kopi Hitam',
          hargaSatuan: 15000,
          qty: 3,
          lacakStok: true,
        ),
        ItemKeranjang(
          produkId: 'p-jasa',
          namaProduk: 'Jasa Antar',
          hargaSatuan: 5000,
          qty: 1,
          lacakStok: false,
        ),
      ];
      final hasil = await repo.checkout(
        tokoId: 't1',
        outletId: 'o1',
        shiftId: 'shift1',
        penggunaId: 'u1',
        metodeBayarId: 'metode-tunai',
        items: items,
        hasil: _hitung(items),
        totalBayar: 50000,
      );

      expect(hasil.subtotal, 3 * 15000 + 5000);
      expect(hasil.total, hasil.subtotal);
      expect(hasil.kembalian, 50000 - hasil.subtotal);

      final transaksiRows = await db.select(db.transaksi).get();
      expect(transaksiRows, hasLength(1));
      expect(transaksiRows.single.nomorStruk, hasil.nomorStruk);
      expect(transaksiRows.single.total, hasil.total);

      final itemRows = await db.select(db.itemTransaksi).get();
      expect(itemRows, hasLength(2));

      final pembayaranRows = await db.select(db.pembayaran).get();
      expect(pembayaranRows, hasLength(1));
      expect(pembayaranRows.single.jumlah, 50000);

      final stokBarang =
          await (db.select(db.stok)..where(
                (t) => t.outletId.equals('o1') & t.produkId.equals('p-barang'),
              ))
              .getSingle();
      expect(stokBarang.jumlah, 10 - 3);

      final stokJasa = await (db.select(
        db.stok,
      )..where((t) => t.produkId.equals('p-jasa'))).getSingleOrNull();
      expect(
        stokJasa,
        isNull,
        reason: 'item tanpa lacakStok tidak boleh ikut bikin baris stok',
      );
    },
  );

  test(
    'Tahap 5b - checkout oleh kasir B menyimpan penggunaId kasir B (bukan kasir lain)',
    () async {
      final items = const [
        ItemKeranjang(
          produkId: 'p-jasa',
          namaProduk: 'Jasa Antar',
          hargaSatuan: 5000,
          qty: 1,
          lacakStok: false,
        ),
      ];
      await repo.checkout(
        tokoId: 't1',
        outletId: 'o1',
        shiftId: 'shift1',
        penggunaId: 'kasir-a',
        metodeBayarId: 'metode-tunai',
        items: items,
        hasil: _hitung(items),
        totalBayar: 5000,
      );
      final hasilKasirB = await repo.checkout(
        tokoId: 't1',
        outletId: 'o1',
        shiftId: 'shift1',
        penggunaId: 'kasir-b',
        metodeBayarId: 'metode-tunai',
        items: items,
        hasil: _hitung(items),
        totalBayar: 5000,
      );

      final transaksiKasirA = await (db.select(
        db.transaksi,
      )..where((t) => t.penggunaId.equals('kasir-a'))).getSingle();
      final transaksiKasirB = await (db.select(
        db.transaksi,
      )..where((t) => t.id.equals(hasilKasirB.id))).getSingle();

      expect(transaksiKasirA.penggunaId, 'kasir-a');
      expect(transaksiKasirB.penggunaId, 'kasir-b');
    },
  );

  test(
    'checkout dengan pajak aktif menghitung total dan menyimpan TransaksiPajak',
    () async {
      final items = const [
        ItemKeranjang(
          produkId: 'p-barang',
          namaProduk: 'Kopi Hitam',
          hargaSatuan: 15000,
          qty: 2,
          lacakStok: true,
        ),
      ];
      final pajakDefault = [
        const k.PajakInput(
          id: 'pajak1',
          nama: 'PPN',
          persen: 11,
          termasukHarga: false,
          urutan: 0,
        ),
      ];
      final hasil = await repo.checkout(
        tokoId: 't1',
        outletId: 'o1',
        shiftId: 'shift1',
        penggunaId: 'u1',
        metodeBayarId: 'metode-tunai',
        items: items,
        hasil: _hitung(items, pajakDefault: pajakDefault),
        totalBayar: 50000,
      );

      // subtotal = 30.000, PPN 11% = 3.300
      expect(hasil.subtotal, 30000);
      expect(hasil.totalPajak, 3300);
      expect(hasil.total, 33300);

      final transaksiPajakRows = await db.select(db.transaksiPajak).get();
      expect(transaksiPajakRows, hasLength(1));
      expect(transaksiPajakRows.single.jumlah, 3300);
    },
  );

  test(
    'voidTransaksi membalikkan stok yang sudah terdebet saat checkout',
    () async {
      final items = const [
        ItemKeranjang(
          produkId: 'p-barang',
          namaProduk: 'Kopi Hitam',
          hargaSatuan: 15000,
          qty: 4,
          lacakStok: true,
        ),
      ];
      final hasil = await repo.checkout(
        tokoId: 't1',
        outletId: 'o1',
        shiftId: 'shift1',
        penggunaId: 'u1',
        metodeBayarId: 'metode-tunai',
        items: items,
        hasil: _hitung(items),
        totalBayar: 60000,
      );

      final stokSetelahJual =
          await (db.select(db.stok)..where(
                (t) => t.outletId.equals('o1') & t.produkId.equals('p-barang'),
              ))
              .getSingle();
      expect(stokSetelahJual.jumlah, 10 - 4);

      await repo.voidTransaksi(
        transaksiId: hasil.id,
        tokoId: 't1',
        outletId: 'o1',
        alasan: 'Salah input',
        disetujuiOleh: 'owner1',
        items: hasil.items,
      );

      final transaksiSetelahVoid = await (db.select(
        db.transaksi,
      )..where((t) => t.id.equals(hasil.id))).getSingle();
      expect(transaksiSetelahVoid.status, TransaksiStatus.dibatalkan);
      expect(transaksiSetelahVoid.alasanVoid, 'Salah input');
      expect(transaksiSetelahVoid.voidDisetujuiOleh, 'owner1');

      final stokSetelahVoid =
          await (db.select(db.stok)..where(
                (t) => t.outletId.equals('o1') & t.produkId.equals('p-barang'),
              ))
              .getSingle();
      expect(
        stokSetelahVoid.jumlah,
        10,
        reason: 'stok harus balik ke saldo sebelum terjual',
      );
    },
  );

  test(
    'watchRiwayat mengembalikan ringkasan dgn jumlah item & metode bayar',
    () async {
      final items = const [
        ItemKeranjang(
          produkId: 'p-barang',
          namaProduk: 'Kopi Hitam',
          hargaSatuan: 15000,
          qty: 2,
          lacakStok: true,
        ),
        ItemKeranjang(
          produkId: 'p-jasa',
          namaProduk: 'Jasa Antar',
          hargaSatuan: 5000,
          qty: 1,
          lacakStok: false,
        ),
      ];
      await repo.checkout(
        tokoId: 't1',
        outletId: 'o1',
        shiftId: 'shift1',
        penggunaId: 'u1',
        metodeBayarId: 'metode-tunai-default',
        items: items,
        hasil: _hitung(items),
        totalBayar: 50000,
      );

      final daftar = await repo.watchRiwayat('o1').first;
      expect(daftar, hasLength(1));
      expect(daftar.single.jumlahItem, 2);
      expect(daftar.single.metodeBayarId, 'metode-tunai-default');
      expect(daftar.single.status, TransaksiStatus.selesai);
    },
  );

  test(
    'detailTransaksi menyusun item+pajak+promo dari transaksi tersimpan',
    () async {
      final items = const [
        ItemKeranjang(
          produkId: 'p-barang',
          namaProduk: 'Kopi Hitam',
          hargaSatuan: 15000,
          qty: 2,
          lacakStok: true,
        ),
      ];
      final hasil = await repo.checkout(
        tokoId: 't1',
        outletId: 'o1',
        shiftId: 'shift1',
        penggunaId: 'u1',
        metodeBayarId: 'metode-tunai-default',
        items: items,
        hasil: _hitung(items),
        totalBayar: 30000,
      );

      final detail = await repo.detailTransaksi(hasil.id);
      expect(detail.items, hasLength(1));
      expect(detail.items.single.namaProduk, 'Kopi Hitam');
      expect(detail.total, 30000);
      expect(detail.metodeBayarId, 'metode-tunai-default');
    },
  );

  test(
    'voidTransaksiLama membalikkan stok tanpa butuh items dari pemanggil',
    () async {
      final items = const [
        ItemKeranjang(
          produkId: 'p-barang',
          namaProduk: 'Kopi Hitam',
          hargaSatuan: 15000,
          qty: 3,
          lacakStok: true,
        ),
      ];
      final hasil = await repo.checkout(
        tokoId: 't1',
        outletId: 'o1',
        shiftId: 'shift1',
        penggunaId: 'u1',
        metodeBayarId: 'metode-tunai-default',
        items: items,
        hasil: _hitung(items),
        totalBayar: 50000,
      );

      await repo.voidTransaksiLama(
        transaksiId: hasil.id,
        tokoId: 't1',
        outletId: 'o1',
        alasan: 'Salah input',
        disetujuiOleh: 'owner1',
      );

      final transaksiSetelahVoid = await (db.select(
        db.transaksi,
      )..where((t) => t.id.equals(hasil.id))).getSingle();
      expect(transaksiSetelahVoid.status, TransaksiStatus.dibatalkan);

      final stokSetelahVoid =
          await (db.select(db.stok)..where(
                (t) => t.outletId.equals('o1') & t.produkId.equals('p-barang'),
              ))
              .getSingle();
      expect(
        stokSetelahVoid.jumlah,
        10,
        reason:
            'stok harus balik walau lacakStok direkonstruksi dari master Produk',
      );
    },
  );

  test(
    'temuan#1 - checkout dgn diskon member DAN promo kode sekaligus menyimpan 2 baris TransaksiPromo (dulu crash di sync/detail)',
    () async {
      final items = const [
        ItemKeranjang(
          produkId: 'p-barang',
          namaProduk: 'Kopi Hitam',
          hargaSatuan: 15000,
          qty: 2,
          lacakStok: true,
        ),
      ];
      final hasil = k.hitung(
        k.TransaksiInput(
          items: [
            for (final item in items)
              k.ItemInput(
                produkId: item.produkId,
                varianId: null,
                namaProduk: item.namaProduk,
                qty: item.qty,
                hargaJual: item.hargaSatuan,
              ),
          ],
          fiturAktif: const {'diskon_member'},
          diskonMemberPersen: 10,
          promo: const k.PromoInput(
            id: 'promo1',
            nama: 'Promo Lebaran',
            tipe: 'nominal',
            cakupan: 'transaksi',
            nilai: 5000,
          ),
        ),
      );
      expect(hasil.diskonMember, greaterThan(0));
      expect(hasil.diskonPromo, greaterThan(0));

      final checkoutHasil = await repo.checkout(
        tokoId: 't1',
        outletId: 'o1',
        shiftId: 'shift1',
        penggunaId: 'u1',
        metodeBayarId: 'metode-tunai-default',
        items: items,
        hasil: hasil,
        totalBayar: hasil.total,
        promo: const domain_promo.Promo(
          id: 'promo1',
          tokoId: 't1',
          nama: 'Promo Lebaran',
          tipe: PromoTipe.nominal,
          nilai: 5000,
          cakupan: PromoCakupan.transaksi,
          minBelanja: 0,
          aktif: true,
        ),
      );

      final promoRows = await db.select(db.transaksiPromo).get();
      expect(promoRows, hasLength(2));

      // Dulu detailTransaksi() CRASH (StateError) kalau ada 2 baris
      // TransaksiPromo - sekarang harus baca "Promo Lebaran" (promo
      // sungguhan), bukan "Diskon member".
      final detail = await repo.detailTransaksi(checkoutHasil.id);
      expect(detail.namaPromo, 'Promo Lebaran');
    },
  );

  test(
    'temuan#1 - daftarPajakAktif dicocokkan ke pajakId per baris TransaksiPajak',
    () async {
      final items = const [
        ItemKeranjang(
          produkId: 'p-barang',
          namaProduk: 'Kopi Hitam',
          hargaSatuan: 15000,
          qty: 2,
          lacakStok: true,
        ),
      ];
      final pajakDefault = [
        const k.PajakInput(
          id: 'pajak-ppn-asli',
          nama: 'PPN',
          persen: 11,
          termasukHarga: false,
          urutan: 0,
        ),
      ];
      final hasil = await repo.checkout(
        tokoId: 't1',
        outletId: 'o1',
        shiftId: 'shift1',
        penggunaId: 'u1',
        metodeBayarId: 'metode-tunai',
        items: items,
        hasil: _hitung(items, pajakDefault: pajakDefault),
        totalBayar: 50000,
        daftarPajakAktif: const [
          domain_pajak.Pajak(
            id: 'pajak-ppn-asli',
            tokoId: 't1',
            nama: 'PPN',
            tipe: PajakTipe.pajak,
            persen: 11,
            termasukHarga: false,
            urutan: 0,
            aktif: true,
          ),
        ],
      );

      final pajakRows = await db.select(db.transaksiPajak).get();
      expect(pajakRows, hasLength(1));
      expect(pajakRows.single.pajakId, 'pajak-ppn-asli');
      expect(hasil.totalPajak, 3300);
    },
  );
}
