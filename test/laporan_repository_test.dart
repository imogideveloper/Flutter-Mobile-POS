import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/core/harga/kalkulator.dart' as k;
import 'package:apps_pos/features/laporan/data/laporan_repository.dart';
import 'package:apps_pos/features/produk/data/local/tables/produk_table.dart';
import 'package:apps_pos/features/transaksi/data/transaksi_repository.dart';
import 'package:apps_pos/features/transaksi/domain/item_keranjang.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Lihat catatan sama di transaksi_repository_test.dart - satu mesin
/// hitung yg sama dgn produksi (tahap 3a bagian A).
k.HasilKalkulasi _hitung(List<ItemKeranjang> items) {
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
    ),
  );
}

void main() {
  late AppDatabase db;
  late TransaksiRepository transaksiRepo;
  late LaporanRepository laporanRepo;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    transaksiRepo = TransaksiRepository(
      db.transaksiDao,
      db.stokDao,
      db.produkDao,
    );
    laporanRepo = LaporanRepository(db.transaksiDao);

    await db.produkDao.upsertProduk(
      ProdukCompanion.insert(
        id: 'p1',
        tokoId: 't1',
        nama: 'Kopi Hitam',
        tipe: ProdukTipe.barang,
        hargaJual: const Value(15000),
        createdAt: 0,
        updatedAt: 0,
      ),
    );
  });

  tearDown(() => db.close());

  test(
    'ringkasan menghitung penjualan, laba kotor, transaksi, dan produk terlaris',
    () async {
      final items1 = const [
        ItemKeranjang(
          produkId: 'p1',
          namaProduk: 'Kopi Hitam',
          hargaSatuan: 15000,
          qty: 3,
          lacakStok: false,
        ),
      ];
      await transaksiRepo.checkout(
        tokoId: 't1',
        outletId: 'o1',
        shiftId: 'shift1',
        penggunaId: 'u1',
        metodeBayarId: 'metode-tunai-default',
        items: items1,
        hasil: _hitung(items1),
        totalBayar: 45000,
      );

      final items2 = const [
        ItemKeranjang(
          produkId: 'p1',
          namaProduk: 'Kopi Hitam',
          hargaSatuan: 15000,
          qty: 1,
          lacakStok: false,
        ),
      ];
      await transaksiRepo.checkout(
        tokoId: 't1',
        outletId: 'o1',
        shiftId: 'shift1',
        penggunaId: 'u1',
        metodeBayarId: 'metode-qris-default',
        items: items2,
        hasil: _hitung(items2),
        totalBayar: 15000,
      );

      final ringkasan = await laporanRepo.ringkasan(
        'o1',
        PeriodeLaporan.hariIni,
      );

      expect(ringkasan.jumlahTransaksi, 2);
      expect(ringkasan.penjualanBersih, 3 * 15000 + 15000);
      // hppSatuan default 0 saat checkout tanpa HPP diset, jadi laba kotor = penjualan.
      expect(ringkasan.labaKotor, 3 * 15000 + 15000);
      expect(ringkasan.rataRata, (3 * 15000 + 15000) ~/ 2);

      expect(ringkasan.metodeBayar, hasLength(2));
      final tunai = ringkasan.metodeBayar.firstWhere(
        (m) => m.metodeBayarId == 'metode-tunai-default',
      );
      expect(tunai.total, 45000);
      expect(tunai.persen, closeTo(75, 0.01));

      expect(ringkasan.produkTerlaris, hasLength(1));
      expect(ringkasan.produkTerlaris.single.namaProduk, 'Kopi Hitam');
      expect(ringkasan.produkTerlaris.single.qty, 4);

      expect(ringkasan.jamRamai, isNotEmpty);
    },
  );

  test('transaksi void tidak ikut dihitung di ringkasan', () async {
    final itemsVoid = const [
      ItemKeranjang(
        produkId: 'p1',
        namaProduk: 'Kopi Hitam',
        hargaSatuan: 15000,
        qty: 1,
        lacakStok: false,
      ),
    ];
    final hasil = await transaksiRepo.checkout(
      tokoId: 't1',
      outletId: 'o1',
      shiftId: 'shift1',
      penggunaId: 'u1',
      metodeBayarId: 'metode-tunai-default',
      items: itemsVoid,
      hasil: _hitung(itemsVoid),
      totalBayar: 15000,
    );

    await transaksiRepo.voidTransaksiLama(
      transaksiId: hasil.id,
      tokoId: 't1',
      outletId: 'o1',
      alasan: 'Salah input',
      disetujuiOleh: 'owner1',
    );

    final ringkasan = await laporanRepo.ringkasan('o1', PeriodeLaporan.hariIni);
    expect(ringkasan.jumlahTransaksi, 0);
    expect(ringkasan.penjualanBersih, 0);
  });

  test('ringkasan rentang custom (F3.C) hanya hitung transaksi di dalam rentang', () async {
    final items = const [
      ItemKeranjang(
        produkId: 'p1',
        namaProduk: 'Kopi Hitam',
        hargaSatuan: 15000,
        qty: 1,
        lacakStok: false,
      ),
    ];
    final hasil = await transaksiRepo.checkout(
      tokoId: 't1',
      outletId: 'o1',
      shiftId: 'shift1',
      penggunaId: 'u1',
      metodeBayarId: 'metode-tunai-default',
      items: items,
      hasil: _hitung(items),
      totalBayar: 15000,
    );
    // Mundurkan tanggal transaksi ini ke 20 hari lalu, di luar "7 hari".
    await (db.update(db.transaksi)..where((t) => t.id.equals(hasil.id))).write(
      TransaksiCompanion(
        tanggal: Value(DateTime.now().toUtc().subtract(const Duration(days: 20)).millisecondsSinceEpoch),
      ),
    );

    final ringkasanSempit = await laporanRepo.ringkasan(
      'o1',
      PeriodeLaporan.custom,
      rentangCustom: (DateTime.now().subtract(const Duration(days: 6)), DateTime.now()),
    );
    expect(ringkasanSempit.jumlahTransaksi, 0);

    final ringkasanLebar = await laporanRepo.ringkasan(
      'o1',
      PeriodeLaporan.custom,
      rentangCustom: (DateTime.now().subtract(const Duration(days: 25)), DateTime.now()),
    );
    expect(ringkasanLebar.jumlahTransaksi, 1);
  });

  test(
    'temuan A.1 (tahap 5) - QRIS manual dipisah dari QRIS biasa di breakdown metode bayar',
    () async {
      final items = const [
        ItemKeranjang(
          produkId: 'p1',
          namaProduk: 'Kopi Hitam',
          hargaSatuan: 15000,
          qty: 1,
          lacakStok: false,
        ),
      ];
      await transaksiRepo.checkout(
        tokoId: 't1',
        outletId: 'o1',
        shiftId: 'shift1',
        penggunaId: 'u1',
        metodeBayarId: 'metode-qris',
        items: items,
        hasil: _hitung(items),
        totalBayar: 15000,
        payloadGateway: '{"metode":"qris_statis_manual","dikonfirmasi_kasir":true}',
      );
      await transaksiRepo.checkout(
        tokoId: 't1',
        outletId: 'o1',
        shiftId: 'shift1',
        penggunaId: 'u1',
        metodeBayarId: 'metode-qris',
        items: items,
        hasil: _hitung(items),
        totalBayar: 15000,
      );

      final ringkasan = await laporanRepo.ringkasan('o1', PeriodeLaporan.hariIni);
      expect(ringkasan.metodeBayar, hasLength(2));
      final labels = ringkasan.metodeBayar.map((m) => m.labelOverride).toSet();
      expect(labels, {'QRIS manual (belum terverifikasi)', null});
    },
  );

  group('rentangLaporanMelebihiBatas (F3.C gating paket)', () {
    test('paket tanpa batas (Bisnis) tidak pernah menolak rentang apa pun', () {
      expect(rentangLaporanMelebihiBatas(jumlahHari: 9999, batasHari: null), isFalse);
    });

    test('rentang dalam batas paket diterima', () {
      expect(rentangLaporanMelebihiBatas(jumlahHari: 30, batasHari: 30), isFalse);
    });

    test('rentang melebihi batas paket ditolak', () {
      expect(rentangLaporanMelebihiBatas(jumlahHari: 31, batasHari: 30), isTrue);
    });
  });
}
