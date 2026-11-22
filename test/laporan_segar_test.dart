import 'dart:async';

import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/core/harga/kalkulator.dart' as k;
import 'package:apps_pos/core/providers/database_provider.dart';
import 'package:apps_pos/core/providers/session_provider.dart';
import 'package:apps_pos/features/laporan/domain/ringkasan_laporan.dart';
import 'package:apps_pos/features/laporan/presentation/providers/laporan_providers.dart';
import 'package:apps_pos/features/transaksi/data/transaksi_repository.dart';
import 'package:apps_pos/features/transaksi/domain/item_keranjang.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Laporan harus ikut berubah saat ada penjualan baru atau refund, tanpa pengguna mengganti periode
/// (ditemukan SIT di HP 2026-11-22: tab Laporan tetap menampilkan angka lama setelah refund).
void main() {
  test('ringkasan laporan dihitung ulang setelah penjualan baru dan setelah refund', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWith((ref) => db),
    ]);
    addTearDown(container.dispose);
    // Dengarkan terus, seperti layar Laporan yang terbuka.
    final dengar = container.listen(ringkasanLaporanProvider, (_, _) {});
    addTearDown(dengar.close);

    Future<RingkasanLaporan> tunggu(bool Function(RingkasanLaporan) cocok) async {
      for (var i = 0; i < 50; i++) {
        final nilai = container.read(ringkasanLaporanProvider).value;
        if (nilai != null && cocok(nilai)) return nilai;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      fail('Laporan tidak ikut berubah: ${container.read(ringkasanLaporanProvider)}');
    }

    expect((await tunggu((r) => r.jumlahTransaksi == 0)).penjualanBersih, 0);

    final repo = TransaksiRepository(db.transaksiDao, db.stokDao, db.produkDao);
    final items = [
      const ItemKeranjang(produkId: 'p1', namaProduk: 'Kopi', hargaSatuan: 18000, qty: 1, lacakStok: false),
    ];
    final jual = await repo.checkout(
      tokoId: 't1',
      outletId: outletIdPlaceholder,
      shiftId: 's1',
      penggunaId: 'u1',
      metodeBayarId: 'metode-tunai-default',
      items: items,
      hasil: k.hitung(k.TransaksiInput(items: [
        for (final i in items)
          k.ItemInput(produkId: i.produkId, varianId: null, namaProduk: i.namaProduk, qty: i.qty, hargaJual: i.hargaSatuan),
      ])),
      totalBayar: 18000,
    );
    expect((await tunggu((r) => r.jumlahTransaksi == 1)).penjualanBersih, 18000, reason: 'penjualan baru langsung tampil');

    // Urutan sama dengan alur refund di aplikasi: nominal dicatat dulu, status menyusul.
    await db.transaksiDao.catatRefundLokal(
      id: 'r1',
      transaksiId: jual.id,
      nomor: 'RFD-1',
      alasan: 'uji',
      total: 9000,
      kembalikanStok: true,
      now: 1,
    );
    await db.transaksiDao.terapkanStatusRefund(transaksiId: jual.id, statusServer: 'refund_sebagian', now: 2);
    final sebagian = await tunggu((r) => r.penjualanBersih != 18000);
    expect(sebagian.penjualanBersih, 9000, reason: 'refund sebagian langsung mengurangi');

    await db.transaksiDao.terapkanStatusRefund(transaksiId: jual.id, statusServer: 'refund', now: 3);
    final penuh = await tunggu((r) => r.jumlahTransaksi == 0);
    expect(penuh.penjualanBersih, 0, reason: 'refund penuh langsung tidak dihitung');
  });
}
