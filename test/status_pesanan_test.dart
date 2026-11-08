import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/core/harga/kalkulator.dart' as k;
import 'package:apps_pos/features/transaksi/data/local/tables/transaksi_table.dart' show StatusPesanan, TransaksiStatus;
import 'package:apps_pos/features/transaksi/data/transaksi_repository.dart';
import 'package:apps_pos/features/transaksi/domain/item_keranjang.dart';
import 'package:apps_pos/features/transaksi/presentation/pages/status_pesanan_page.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

/// Status pesanan (dokumen IMOGI no. 26): disimpan saat checkout, diubah
/// lewat halaman Status Pesanan, dan perubahannya dilacak untuk sync.
void main() {
  late AppDatabase db;
  late TransaksiRepository repo;

  const items = [
    ItemKeranjang(produkId: 'p-1', namaProduk: 'Kopi Susu', hargaSatuan: 18000, qty: 2, lacakStok: false),
  ];

  k.HasilKalkulasi hitung() => k.hitung(
        k.TransaksiInput(items: [
          k.ItemInput(produkId: 'p-1', varianId: null, namaProduk: 'Kopi Susu', qty: 2, hargaJual: 18000),
        ]),
      );

  Future<dynamic> bayar({StatusPesanan? statusAwal, String outletId = 'o1'}) => repo.checkout(
        tokoId: 't1',
        outletId: outletId,
        shiftId: 's1',
        penggunaId: 'u1',
        metodeBayarId: 'm1',
        items: items,
        hasil: hitung(),
        totalBayar: 36000,
        statusAwal: statusAwal,
      );

  Future<TransaksiRow> ambil(String id) => (db.select(db.transaksi)..where((t) => t.id.equals(id))).getSingle();

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = TransaksiRepository(db.transaksiDao, db.stokDao, db.produkDao);
  });

  tearDown(() => db.close());

  group('repository', () {
    test('checkout menyimpan status awal, atau kosong bila fitur mati', () async {
      final a = await bayar(statusAwal: StatusPesanan.baru);
      final b = await bayar();
      expect((await ambil(a.id as String)).statusPesanan, StatusPesanan.baru);
      expect((await ambil(b.id as String)).statusPesanan, isNull);
    });

    test('ubahStatusPesanan mengganti status dan mencatat waktu perubahan', () async {
      final h = await bayar(statusAwal: StatusPesanan.baru);
      await repo.ubahStatusPesanan(h.id as String, StatusPesanan.diproses);
      final row = await ambil(h.id as String);
      expect(row.statusPesanan, StatusPesanan.diproses);
      expect(row.statusPesananDiubahPada, isNotNull);
    });

    test('pesananHariIni hanya memuat pesanan berstatus, outlet ini, hari ini, tidak di-void', () async {
      final a = await bayar(statusAwal: StatusPesanan.baru);
      await bayar(); // tanpa status
      await bayar(statusAwal: StatusPesanan.baru, outletId: 'o-lain');
      final void_ = await bayar(statusAwal: StatusPesanan.baru);
      await db.transaksiDao.voidTransaksi(
        transaksiId: void_.id as String,
        alasan: 'salah',
        disetujuiOleh: 'u1',
        now: 1,
      );

      final daftar = await repo.pesananHariIni('o1');
      expect(daftar.map((p) => p.id), [a.id]);
      expect(daftar.single.ringkasanItem, '2x Kopi Susu');
      expect(daftar.single.status, StatusPesanan.baru);
    });

    test('pesanan kemarin tidak ikut daftar hari ini', () async {
      final h = await bayar(statusAwal: StatusPesanan.baru);
      expect((await repo.pesananHariIni('o1', sekarang: DateTime.now().add(const Duration(days: 2)))), isEmpty);
      expect((await repo.pesananHariIni('o1')).map((p) => p.id), [h.id]);
    });
  });

  group('pelacak sinkron status', () {
    test('transaksi yang belum tersync tidak dihitung (statusnya ikut payload transaksi)', () async {
      final h = await bayar(statusAwal: StatusPesanan.baru);
      await db.transaksiDao.ubahStatusPesanan(h.id as String, StatusPesanan.siap, 1000);
      expect(await db.transaksiDao.statusPesananBelumSync(), isEmpty);
    });

    test('status yang diubah setelah transaksi tersync ikut daftar, lalu hilang setelah ditandai', () async {
      final h = await bayar(statusAwal: StatusPesanan.baru);
      final id = h.id as String;
      await db.transaksiDao.tandaiSudahSync([id], 2000);

      await db.transaksiDao.ubahStatusPesanan(id, StatusPesanan.diproses, 3000);
      expect((await db.transaksiDao.statusPesananBelumSync()).map((r) => r.id), [id]);

      await db.transaksiDao.tandaiStatusPesananSudahSync([id], 4000);
      expect(await db.transaksiDao.statusPesananBelumSync(), isEmpty);

      await db.transaksiDao.ubahStatusPesanan(id, StatusPesanan.siap, 5000);
      expect((await db.transaksiDao.statusPesananBelumSync()).map((r) => r.id), [id]);
    });

    test('mengirim transaksi menandai status ikut terkirim (versi terbaru ada di payload)', () async {
      final h = await bayar(statusAwal: StatusPesanan.baru);
      final id = h.id as String;
      await db.transaksiDao.ubahStatusPesanan(id, StatusPesanan.siap, 1000);
      await db.transaksiDao.tandaiSudahSync([id], 2000);
      expect(await db.transaksiDao.statusPesananBelumSync(), isEmpty);
      expect((await ambil(id)).status, TransaksiStatus.selesai);
    });
  });

  group('halaman Status Pesanan', () {
    Future<void> buka(WidgetTester tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: overridesSudahLogin(db),
        child: const MaterialApp(home: StatusPesananPage()),
      ));
      await tester.pumpAndSettle();
    }

    Future<void> tutup(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 1));
    }

    testWidgets('kosong: pesan belum ada pesanan', (tester) async {
      await buka(tester);
      expect(find.text('Belum ada pesanan hari ini'), findsOneWidget);
      await tutup(tester);
    });

    testWidgets('memajukan pesanan tahap demi tahap sampai Selesai', (tester) async {
      // Outlet bawaan aplikasi ('outlet-default') = outlet yang dibaca halaman ini.
      final h = await bayar(statusAwal: StatusPesanan.baru, outletId: 'outlet-default');
      final id = h.id as String;
      await buka(tester);

      expect(find.byKey(Key('statusPesanan.status.$id')), findsOneWidget);
      expect(find.text('Baru'), findsOneWidget);
      expect(find.text('2x Kopi Susu'), findsOneWidget);

      await tester.tap(find.byKey(Key('statusPesanan.maju.$id')));
      await tester.pumpAndSettle();
      expect(find.text('Diproses'), findsOneWidget);
      expect((await ambil(id)).statusPesanan, StatusPesanan.diproses);

      await tester.tap(find.byKey(Key('statusPesanan.maju.$id')));
      await tester.pumpAndSettle();
      expect(find.text('Siap'), findsOneWidget);

      await tester.tap(find.byKey(Key('statusPesanan.maju.$id')));
      await tester.pumpAndSettle();
      expect((await ambil(id)).statusPesanan, StatusPesanan.selesai);
      expect(find.byKey(Key('statusPesanan.maju.$id')), findsNothing, reason: 'tahap akhir tidak punya tombol maju');
      expect(find.textContaining('Selesai hari ini'), findsOneWidget);
      expect(find.text('Semua pesanan sudah selesai'), findsOneWidget);
      await tutup(tester);
    });
  });
}
