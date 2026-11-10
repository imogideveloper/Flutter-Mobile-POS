import 'dart:async';
import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/core/harga/kalkulator.dart' as k;
import 'package:apps_pos/core/providers/database_provider.dart';
import 'package:apps_pos/features/transaksi/data/local/tables/metode_bayar_table.dart';
import 'package:apps_pos/features/transaksi/data/transaksi_repository.dart';
import 'package:apps_pos/features/transaksi/domain/item_keranjang.dart';
import 'package:apps_pos/features/transaksi/domain/metode_bayar_label.dart';
import 'package:apps_pos/features/transaksi/presentation/providers/transaksi_providers.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// BUG-015: metode pembayaran harus tampil di riwayat. Id asli dari server berbentuk UUID,
/// jadi namanya dicari di tabel metode_bayar, bukan dari dua id placeholder lama.
void main() {
  const idTransfer = '3f2b8c1e-0000-4000-8000-000000000001';
  const idTunai = '3f2b8c1e-0000-4000-8000-000000000002';
  const nama = {idTransfer: 'Transfer Bank', idTunai: 'Tunai'};

  group('labelMetodeBayar', () {
    test('id UUID dari server diganti nama dari tabel', () {
      expect(labelMetodeBayar(idTransfer, nama: nama), 'Transfer Bank');
      expect(labelMetodeBayar(idTunai, nama: nama), 'Tunai');
    });

    test('split pembayaran tampil Campuran walau id dikenal', () {
      expect(labelMetodeBayar(idTransfer, jumlahPembayaran: 2, nama: nama), 'Campuran');
    });

    test('id placeholder lama tetap dikenali tanpa peta', () {
      expect(labelMetodeBayar('metode-tunai-default'), 'Tunai');
      expect(labelMetodeBayar('metode-qris-default'), 'QRIS');
    });

    test('id tidak dikenal atau kosong tetap "-" (tidak error)', () {
      expect(labelMetodeBayar('uuid-tak-dikenal', nama: nama), '-');
      expect(labelMetodeBayar(null, nama: nama), '-');
      expect(labelMetodeBayar(idTransfer), '-', reason: 'peta belum termuat');
    });

    test('nama kosong tidak dipakai', () {
      expect(labelMetodeBayar(idTransfer, nama: {idTransfer: '  '}), '-');
    });
  });

  group('riwayat memakai nama dari tabel metode_bayar', () {
    late AppDatabase db;
    late ProviderContainer container;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      container = ProviderContainer(overrides: [appDatabaseProvider.overrideWith((ref) => db)]);
      for (final (id, n, aktif) in [(idTransfer, 'Transfer Bank', true), (idTunai, 'Tunai', false)]) {
        await db.into(db.metodeBayar).insert(MetodeBayarCompanion.insert(
              id: id,
              tokoId: 't1',
              nama: n,
              tipe: id == idTunai ? MetodeBayarTipe.tunai : MetodeBayarTipe.transfer,
              aktif: Value(aktif),
              createdAt: 1,
              updatedAt: 1,
            ));
      }
    });

    /// Provider stream Riverpod 3 baru mengalir bila ada pendengar (seperti widget); `read(.future)` menggantung.
    Future<Map<String, String>> petaNama() {
      final selesai = Completer<Map<String, String>>();
      container.listen(namaMetodeBayarProvider, (_, next) {
        if (next.hasValue && !selesai.isCompleted) selesai.complete(next.requireValue);
      }, fireImmediately: true);
      return selesai.future;
    }

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    test('peta nama memuat juga metode yang sudah dinonaktifkan (transaksi lama masih merujuknya)', () async {
      final peta = await petaNama();
      expect(peta, nama);
    });

    test('transaksi yang dibayar dengan metode asli tampil dengan namanya di daftar riwayat', () async {
      final repo = TransaksiRepository(db.transaksiDao, db.stokDao, db.produkDao);
      const item = ItemKeranjang(produkId: 'p1', namaProduk: 'Kopi', hargaSatuan: 18000, qty: 1, lacakStok: false);
      await repo.checkout(
        tokoId: 't1',
        outletId: 'o1',
        shiftId: 's1',
        penggunaId: 'u1',
        metodeBayarId: idTransfer,
        items: const [item],
        hasil: k.hitung(k.TransaksiInput(items: [
          k.ItemInput(produkId: 'p1', varianId: null, namaProduk: 'Kopi', qty: 1, hargaJual: 18000),
        ])),
        totalBayar: 18000,
      );

      final riwayat = (await repo.watchRiwayat('o1').first).single;
      expect(riwayat.metodeBayarId, idTransfer);
      final peta = await petaNama();
      expect(labelMetodeBayar(riwayat.metodeBayarId, jumlahPembayaran: riwayat.jumlahPembayaran, nama: peta), 'Transfer Bank');
      expect(labelMetodeBayar(riwayat.metodeBayarId, jumlahPembayaran: riwayat.jumlahPembayaran), '-',
          reason: 'perilaku lama (sebelum BUG-015)');
    });
  });
}
