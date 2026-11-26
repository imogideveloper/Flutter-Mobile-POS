import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/core/harga/kalkulator.dart' as k;
import 'package:apps_pos/features/laporan/data/laporan_repository.dart';
import 'package:apps_pos/features/produk/data/local/tables/produk_table.dart';
import 'package:apps_pos/features/transaksi/data/transaksi_repository.dart';
import 'package:apps_pos/features/transaksi/domain/item_keranjang.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Laba kotor, produk terlaris, tren, dan margin di HP harus ikut berkurang oleh refund sebagian (AT1, bagian c).
/// Id item di server berbeda dari id lokal, jadi item direfund dicocokkan lewat (nama, harga).
void main() {
  late AppDatabase db;
  late TransaksiRepository repo;
  late LaporanRepository laporan;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = TransaksiRepository(db.transaksiDao, db.stokDao, db.produkDao);
    laporan = LaporanRepository(db.transaksiDao);
    await db.produkDao.upsertProduk(ProdukCompanion.insert(
      id: 'p1',
      tokoId: 't1',
      nama: 'Kopi',
      tipe: ProdukTipe.barang,
      hargaJual: const Value(18000),
      hpp: const Value(7000),
      createdAt: 0,
      updatedAt: 0,
    ));
  });

  tearDown(() => db.close());

  Future<String> jual(List<int> qtyPerBaris) async {
    final items = [
      for (final q in qtyPerBaris)
        ItemKeranjang(produkId: 'p1', namaProduk: 'Kopi', hargaSatuan: 18000, qty: q.toDouble(), lacakStok: false),
    ];
    final total = qtyPerBaris.fold<int>(0, (a, b) => a + b) * 18000;
    final t = await repo.checkout(
      tokoId: 't1',
      outletId: 'o1',
      shiftId: 's1',
      penggunaId: 'u1',
      metodeBayarId: 'metode-tunai-default',
      items: items,
      hasil: k.hitung(k.TransaksiInput(items: [
        for (final i in items)
          k.ItemInput(produkId: i.produkId, varianId: null, namaProduk: i.namaProduk, qty: i.qty, hargaJual: i.hargaSatuan),
      ])),
      totalBayar: total,
    );
    return t.id;
  }

  Future<void> refund(
    String transaksiId, {
    required String refundId,
    required double qty,
    required int jumlah,
    bool kembalikanStok = true,
    String status = 'refund_sebagian',
    int hargaSatuan = 18000,
  }) async {
    await db.transaksiDao.catatRefundLokal(
      id: refundId,
      transaksiId: transaksiId,
      nomor: 'RFD-$refundId',
      alasan: 'uji',
      total: jumlah,
      kembalikanStok: kembalikanStok,
      now: 1,
    );
    await db.transaksiDao.catatItemRefundLokal(
      refundId: refundId,
      transaksiId: transaksiId,
      items: [(namaProduk: 'Kopi', hargaSatuan: hargaSatuan, qty: qty, jumlah: jumlah)],
      now: 1,
    );
    await db.transaksiDao.terapkanStatusRefund(transaksiId: transaksiId, statusServer: status, now: 2);
  }

  test('diskon transaksi (member) ikut mengurangi laba kotor, sama dengan Laba rugi (HP 2026-11-26)', () async {
    final items = [
      const ItemKeranjang(produkId: 'p1', namaProduk: 'Kopi', hargaSatuan: 18000, qty: 2, lacakStok: false),
    ];
    await repo.checkout(
      tokoId: 't1',
      outletId: 'o1',
      shiftId: 's1',
      penggunaId: 'u1',
      metodeBayarId: 'metode-tunai-default',
      items: items,
      hasil: k.hitung(k.TransaksiInput(
        items: [
          for (final i in items)
            k.ItemInput(produkId: i.produkId, varianId: null, namaProduk: i.namaProduk, qty: i.qty, hargaJual: i.hargaSatuan),
        ],
        fiturAktif: const {'diskon_member'},
        diskonMemberPersen: 10,
      )),
      totalBayar: 32400,
    );
    final r = await laporan.ringkasan('o1', PeriodeLaporan.hariIni);
    expect(r.penjualanBersih, 32400, reason: '36.000 dikurangi diskon member 3.600');
    expect(r.labaKotor, 32400 - 14000, reason: 'penjualan bersih dikurangi HPP 7.000 x 2');
  });

  test('tanpa refund: laba kotor, tren, dan produk terlaris seperti biasa', () async {
    await jual([2]);
    final r = await laporan.ringkasan('o1', PeriodeLaporan.hariIni);
    expect(r.labaKotor, 22000);
    expect(r.trenProduk.single.omzet, 36000);
    expect(r.produkTerlaris.single.qty, 2);
    expect(r.marginProduk.single.hpp, 14000);
  });

  test('refund sebagian dengan barang kembali ke stok: laba kotor dan produk ikut berkurang', () async {
    final id = await jual([2]);
    await refund(id, refundId: 'r1', qty: 1, jumlah: 18000);
    final r = await laporan.ringkasan('o1', PeriodeLaporan.hariIni);
    expect(r.labaKotor, 11000, reason: '(18.000 - 7.000) x 1 yang masih terjual');
    expect(r.trenProduk.single.omzet, 18000);
    expect(r.produkTerlaris.single.qty, 1);
    expect(r.produkTerlaris.single.total, 18000);
    expect(r.marginProduk.single.omzet, 18000);
    expect(r.marginProduk.single.hpp, 7000);
  });

  test('refund tanpa kembali ke stok: HPP barang yang direfund tetap ditanggung', () async {
    final id = await jual([2]);
    await refund(id, refundId: 'r1', qty: 1, jumlah: 18000, kembalikanStok: false);
    final r = await laporan.ringkasan('o1', PeriodeLaporan.hariIni);
    expect(r.labaKotor, 4000, reason: '18.000 x 1 dikurangi HPP 7.000 x 2');
    expect(r.marginProduk.single.hpp, 14000);
    expect(r.produkTerlaris.single.qty, 1);
  });

  test('refund penuh: transaksi tidak ikut sama sekali', () async {
    final id = await jual([2]);
    await refund(id, refundId: 'r1', qty: 2, jumlah: 36000, status: 'refund');
    final r = await laporan.ringkasan('o1', PeriodeLaporan.hariIni);
    expect(r.labaKotor, 0);
    expect(r.produkTerlaris, isEmpty);
    expect(r.jumlahTransaksi, 0);
  });

  test('catatItemRefundLokal aman dipanggil ulang dan tidak melebihi qty', () async {
    final id = await jual([2]);
    await refund(id, refundId: 'r1', qty: 1, jumlah: 18000);
    // Panggil ulang untuk refund yang sama: tidak menggandakan.
    await db.transaksiDao.catatItemRefundLokal(
      refundId: 'r1',
      transaksiId: id,
      items: [(namaProduk: 'Kopi', hargaSatuan: 18000, qty: 1.0, jumlah: 18000)],
      now: 3,
    );
    final item = (await db.transaksiDao.itemUntukTransaksi(id)).single;
    expect((await db.transaksiDao.refundPerItem([item.id]))[item.id]!.qty, 1);

    // Refund kedua yang meminta lebih dari sisa: dibatasi sisa qty (1 dari 2 sudah direfund).
    await refund(id, refundId: 'r2', qty: 5, jumlah: 90000);
    expect((await db.transaksiDao.refundPerItem([item.id]))[item.id]!.qty, 2, reason: 'maksimal qty asli');
  });

  test('item dicocokkan lewat nama saja bila harganya tidak persis sama, dan dibagi ke baris yang sama berurutan', () async {
    final id = await jual([2, 2]); // dua baris Kopi @18.000, masing-masing qty 2
    await refund(id, refundId: 'r1', qty: 3, jumlah: 54000, hargaSatuan: 17000); // harga tidak cocok persis
    final baris = await db.transaksiDao.itemUntukTransaksi(id);
    final refundPerItem = await db.transaksiDao.refundPerItem([for (final b in baris) b.id]);
    final jumlahQty = refundPerItem.values.fold<double>(0, (a, b) => a + b.qty);
    expect(jumlahQty, 3);
    expect(refundPerItem.length, 2, reason: '2 pada baris pertama, 1 pada baris kedua');
    final r = await laporan.ringkasan('o1', PeriodeLaporan.hariIni);
    expect(r.produkTerlaris.single.qty, 1, reason: '4 terjual dikurangi 3');
  });

  test('tanpa baris refund lokal, item refund tidak dicatat (transaksi dari HP lain atau tidak ada)', () async {
    final id = await jual([2]);
    await db.transaksiDao.catatItemRefundLokal(
      refundId: 'tidak-ada',
      transaksiId: id,
      items: [(namaProduk: 'Kopi', hargaSatuan: 18000, qty: 1.0, jumlah: 18000)],
      now: 1,
    );
    final item = (await db.transaksiDao.itemUntukTransaksi(id)).single;
    expect(await db.transaksiDao.refundPerItem([item.id]), isEmpty);
  });
}
