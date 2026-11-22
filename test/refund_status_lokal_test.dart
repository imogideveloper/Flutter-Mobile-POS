import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/core/harga/kalkulator.dart' as k;
import 'package:apps_pos/features/transaksi/data/local/tables/transaksi_table.dart';
import 'package:apps_pos/features/transaksi/data/transaksi_repository.dart';
import 'package:apps_pos/features/transaksi/domain/item_keranjang.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late String transaksiId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final repo = TransaksiRepository(db.transaksiDao, db.stokDao, db.produkDao);
    final items = [
      const ItemKeranjang(produkId: 'p1', namaProduk: 'Kopi', hargaSatuan: 18000, qty: 1, lacakStok: false),
    ];
    final hasil = k.hitung(k.TransaksiInput(items: [
      for (final i in items)
        k.ItemInput(produkId: i.produkId, varianId: null, namaProduk: i.namaProduk, qty: i.qty, hargaJual: i.hargaSatuan),
    ]));
    final t = await repo.checkout(
      tokoId: 't1',
      outletId: 'o1',
      shiftId: 's1',
      penggunaId: 'u1',
      metodeBayarId: 'metode-tunai-default',
      items: items,
      hasil: hasil,
      totalBayar: 18000,
    );
    transaksiId = t.id;
  });

  tearDown(() => db.close());

  Future<TransaksiRow> baca() => (db.select(db.transaksi)..where((t) => t.id.equals(transaksiId))).getSingle();

  test('status refund dari server diterapkan ke transaksi lokal tanpa menyentuh penanda sync', () async {
    final sebelum = await baca();
    expect(sebelum.status, TransaksiStatus.selesai);

    await db.transaksiDao.terapkanStatusRefund(transaksiId: transaksiId, statusServer: 'refund', now: 123);

    final sesudah = await baca();
    expect(sesudah.status, TransaksiStatus.refund);
    expect(sesudah.disinkronPada, sebelum.disinkronPada, reason: 'bukan perubahan yang perlu dikirim ke server');
  });

  test('refund sebagian diterapkan sebagai refundSebagian', () async {
    await db.transaksiDao.terapkanStatusRefund(transaksiId: transaksiId, statusServer: 'refund_sebagian', now: 123);
    expect((await baca()).status, TransaksiStatus.refundSebagian);
  });

  test('status lain atau kosong dari server diabaikan', () async {
    for (final nilai in ['selesai', 'void', '', 'aneh']) {
      await db.transaksiDao.terapkanStatusRefund(transaksiId: transaksiId, statusServer: nilai, now: 123);
      expect((await baca()).status, TransaksiStatus.selesai, reason: 'nilai "$nilai" tidak boleh mengubah status');
    }
  });
}
