import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/core/harga/kalkulator.dart' as k;
import 'package:apps_pos/features/laporan/data/laporan_repository.dart';
import 'package:apps_pos/features/laporan/domain/angka_penjualan.dart';
import 'package:apps_pos/features/transaksi/data/transaksi_repository.dart';
import 'package:apps_pos/features/transaksi/domain/item_keranjang.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Keputusan sementara AT1: "Penjualan bersih" = tanpa pajak dan service, setelah refund; pajak dan service
/// serta total penerimaan ditampilkan terpisah. Contoh yang sama dengan uji di HP: Rp18.000 + service 5% +
/// PB1 10% = Rp20.790.
void main() {
  late AppDatabase db;
  late TransaksiRepository repo;
  late LaporanRepository laporan;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = TransaksiRepository(db.transaksiDao, db.stokDao, db.produkDao);
    laporan = LaporanRepository(db.transaksiDao);
  });

  tearDown(() => db.close());

  Future<String> jualKopi() async {
    final items = [
      const ItemKeranjang(produkId: 'p1', namaProduk: 'Kopi', hargaSatuan: 18000, qty: 1, lacakStok: false),
    ];
    final hasil = k.hitung(k.TransaksiInput(
      items: [
        for (final i in items)
          k.ItemInput(produkId: i.produkId, varianId: null, namaProduk: i.namaProduk, qty: i.qty, hargaJual: i.hargaSatuan),
      ],
      serviceDefault: const [
        k.PajakInput(id: 'svc', nama: 'Service Charge', persen: 5, termasukHarga: false, urutan: 0),
      ],
      pajakDefault: const [
        k.PajakInput(id: 'pb1', nama: 'PB1', persen: 10, termasukHarga: false, urutan: 1),
      ],
    ));
    expect(hasil.total, 20790, reason: 'contoh harus sama dengan struk di HP');
    final t = await repo.checkout(
      tokoId: 't1',
      outletId: 'o1',
      shiftId: 's1',
      penggunaId: 'u1',
      metodeBayarId: 'metode-tunai-default',
      items: items,
      hasil: hasil,
      totalBayar: 20790,
    );
    return t.id;
  }

  test('penjualan bersih tanpa pajak dan service; total penerimaan dan pajak terpisah', () async {
    await jualKopi();
    final r = await laporan.ringkasan('o1', PeriodeLaporan.hariIni);
    expect(r.penjualanBersih, 18000);
    expect(r.pajakService, 2790);
    expect(r.totalPenerimaan, 20790);
    expect(r.jumlahTransaksi, 1);
    expect(r.rataRata, 18000);
    expect(r.jamRamai.single.total, 18000, reason: 'jam ramai memakai penjualan bersih yang sama');
    expect(r.penjualanHarian.map((h) => h.total).reduce((a, b) => a + b), 18000);
  });

  test('refund penuh: transaksi tidak lagi dihitung sebagai penjualan', () async {
    final id = await jualKopi();
    await db.transaksiDao.terapkanStatusRefund(transaksiId: id, statusServer: 'refund', now: 1);
    final r = await laporan.ringkasan('o1', PeriodeLaporan.hariIni);
    expect(r.penjualanBersih, 0);
    expect(r.pajakService, 0);
    expect(r.totalPenerimaan, 0);
    expect(r.jumlahTransaksi, 0);
  });

  test('refund sebagian: sisanya tetap penjualan, dikurangi proporsional', () async {
    final id = await jualKopi();
    await db.transaksiDao.terapkanStatusRefund(transaksiId: id, statusServer: 'refund_sebagian', now: 1);
    await db.transaksiDao.catatRefundLokal(
      id: 'r1',
      transaksiId: id,
      nomor: 'RFD-1',
      alasan: 'Uji',
      total: 10395, // separuh dari 20.790
      kembalikanStok: true,
      now: 1,
    );
    final r = await laporan.ringkasan('o1', PeriodeLaporan.hariIni);
    expect(r.penjualanBersih, 9000);
    expect(r.pajakService, 1395);
    expect(r.totalPenerimaan, 10395);
    expect(r.jumlahTransaksi, 1);
  });

  test('refund sebagian yang nominalnya tidak diketahui HP tidak mengurangi apa pun', () async {
    final id = await jualKopi();
    await db.transaksiDao.terapkanStatusRefund(transaksiId: id, statusServer: 'refund_sebagian', now: 1);
    final r = await laporan.ringkasan('o1', PeriodeLaporan.hariIni);
    expect(r.penjualanBersih, 18000);
    expect(r.totalPenerimaan, 20790);
  });

  test('catatRefundLokal mengabaikan transaksi yang tidak ada dan totalRefundPerTransaksi menjumlahkan', () async {
    await db.transaksiDao.catatRefundLokal(
      id: 'r0',
      transaksiId: 'tidak-ada',
      nomor: 'RFD-0',
      alasan: 'x',
      total: 1,
      kembalikanStok: true,
      now: 1,
    );
    expect(await db.transaksiDao.totalRefundPerTransaksi(['tidak-ada']), isEmpty);

    final id = await jualKopi();
    for (final (rid, nominal) in [('a', 1000), ('b', 2500)]) {
      await db.transaksiDao.catatRefundLokal(
        id: rid,
        transaksiId: id,
        nomor: 'RFD-$rid',
        alasan: 'x',
        total: nominal,
        kembalikanStok: false,
        now: 1,
      );
    }
    expect(await db.transaksiDao.totalRefundPerTransaksi([id]), {id: 3500});
  });

  test('angkaPenjualanTransaksi: refund melebihi total dibatasi, tanpa refund apa adanya', () async {
    final id = await jualKopi();
    final row = await db.transaksiDao.transaksiById(id);
    final utuh = angkaPenjualanTransaksi(row);
    expect((utuh.penjualanBersih, utuh.pajakService, utuh.totalPenerimaan), (18000, 2790, 20790));
    final lebih = angkaPenjualanTransaksi(row, refund: 99999);
    expect((lebih.penjualanBersih, lebih.pajakService, lebih.totalPenerimaan), (0, 0, 0));
    final negatif = angkaPenjualanTransaksi(row, refund: -5);
    expect(negatif.totalPenerimaan, 20790, reason: 'refund negatif dianggap 0');
  });
}
