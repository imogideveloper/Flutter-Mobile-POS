import 'dart:convert';

import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/core/harga/kalkulator.dart' as k;
import 'package:apps_pos/features/laporan/data/laporan_repository.dart';
import 'package:apps_pos/features/produk/data/local/tables/produk_table.dart';
import 'package:apps_pos/features/stok/data/local/tables/mutasi_stok_table.dart';
import 'package:apps_pos/features/transaksi/data/transaksi_repository.dart';
import 'package:apps_pos/features/transaksi/domain/item_keranjang.dart';
import 'package:apps_pos/features/transaksi/domain/label_tujuan.dart';
import 'package:apps_pos/features/transaksi/domain/split_pembayaran.dart';
import 'package:apps_pos/main.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

void main() {
  group('label_tujuan', () {
    test('daftarLabelTujuan membuang kosong dan spasi', () {
      expect(daftarLabelTujuan(null), isEmpty);
      expect(daftarLabelTujuan(''), isEmpty);
      expect(daftarLabelTujuan('GoPay, OVO ,,ShopeePay'), ['GoPay', 'OVO', 'ShopeePay']);
    });

    test('normalisasi: rapikan, buang duplikat tanpa membedakan huruf, kosong jadi null', () {
      expect(normalisasiLabelTujuan(' GoPay , ovo,,  gopay , Shopee   Pay ').hasil, 'GoPay,ovo,Shopee Pay');
      expect(normalisasiLabelTujuan('').hasil, isNull);
      expect(normalisasiLabelTujuan(' , ').hasil, isNull);
    });

    test('normalisasi: menolak label terlalu panjang atau terlalu banyak (sama dengan server)', () {
      expect(normalisasiLabelTujuan('x' * 31).galat, isNotNull);
      expect(normalisasiLabelTujuan([for (var i = 0; i < 11; i++) 'L$i'].join(',')).galat, isNotNull);
      expect(normalisasiLabelTujuan([for (var i = 0; i < 10; i++) 'L$i'].join(',')).galat, isNull);
    });

    test('validasi: wajib memilih bila metode punya label', () {
      expect(validasiLabelTujuan(tersedia: const [], pilihan: null), isNull);
      expect(validasiLabelTujuan(tersedia: const ['GoPay'], pilihan: null), isNotNull);
      expect(validasiLabelTujuan(tersedia: const ['GoPay'], pilihan: 'OVO'), isNotNull);
      expect(validasiLabelTujuan(tersedia: const ['GoPay', 'OVO'], pilihan: 'OVO'), isNull);
    });

    test('payload menggabungkan 4 digit kartu dan label tujuan', () {
      expect(payloadPembayaranManual(), isNull);
      expect(jsonDecode(payloadPembayaranManual(labelTujuan: 'GoPay')!), {'label_tujuan': 'GoPay'});
      expect(
        jsonDecode(payloadPembayaranManual(empatDigitAkhirKartu: '1234', labelTujuan: 'BCA')!),
        {'empat_digit_akhir_kartu': '1234', 'label_tujuan': 'BCA'},
      );
      expect(
        jsonDecode(payloadPembayaranManual(empatDigitAkhirKartu: '1234', labelTujuan: 'EDC BCA', jenisKartu: 'debit')!),
        {'empat_digit_akhir_kartu': '1234', 'jenis_kartu': 'debit', 'label_tujuan': 'EDC BCA'},
      );
    });
  });

  test('laporan memisahkan baris per label tujuan untuk rekonsiliasi', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.produkDao.upsertProduk(ProdukCompanion.insert(
      id: 'p1',
      tokoId: 't1',
      nama: 'Kopi',
      tipe: ProdukTipe.barang,
      hargaJual: const Value(10000),
      createdAt: 0,
      updatedAt: 0,
    ));
    final repo = TransaksiRepository(db.transaksiDao, db.stokDao, db.produkDao);
    const item = ItemKeranjang(produkId: 'p1', namaProduk: 'Kopi', hargaSatuan: 10000, qty: 1, lacakStok: false);
    final hasil = k.hitung(k.TransaksiInput(items: [
      k.ItemInput(produkId: 'p1', varianId: null, namaProduk: 'Kopi', qty: 1, hargaJual: 10000),
    ]));
    Future<void> bayar(String? label) => repo.checkout(
          tokoId: 't1',
          outletId: 'o1',
          shiftId: 's1',
          penggunaId: 'u1',
          metodeBayarId: 'm-ewallet',
          items: const [item],
          hasil: hasil,
          totalBayar: 10000,
          splitPembayaran: [SplitPembayaran(metodeBayarId: 'm-ewallet', jumlah: 10000, labelTujuan: label)],
        );
    await bayar('GoPay');
    await bayar('GoPay');
    await bayar('OVO');
    await bayar(null);

    final ringkasan = await LaporanRepository(db.transaksiDao).ringkasan('o1', PeriodeLaporan.hariIni);
    final peta = {for (final m in ringkasan.metodeBayar) m.labelTampil('E-wallet'): m.total};
    expect(peta, {'E-wallet · GoPay': 20000, 'E-wallet · OVO': 10000, 'E-wallet': 10000});
  });

  testWidgets('layar bayar: kartu dengan label tujuan wajib memilih, lalu tersimpan di pembayaran', (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.produkDao.upsertProduk(ProdukCompanion.insert(
      id: 'p1',
      tokoId: 'toko-default',
      nama: 'Kopi Hitam',
      tipe: ProdukTipe.barang,
      hargaJual: const Value(50000),
      createdAt: 0,
      updatedAt: 0,
    ));
    await db.stokDao.catatMutasi(
      tokoId: 'toko-default',
      outletId: 'outlet-default',
      produkId: 'p1',
      jenis: MutasiJenis.stokAwal,
      qty: 10,
    );
    await seedMetodeBayarUjiCoba(db);
    await db.metodeBayarDao.ubahLabelTujuan('metode-kartu-uji', 'BCA,Mandiri', now: 1);

    await tester.pumpWidget(ProviderScope(overrides: overridesSudahLogin(db), child: const AppsPosApp()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Buka Shift'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('bukaShiftForm.modalAwal')), '0');
    await tester.tap(find.text('Mulai shift'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kopi Hitam'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lihat keranjang'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bayar Rp50.000'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Kartu').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('bayarForm.labelTujuan')), findsOneWidget);

    // Belum memilih label -> ditolak.
    await tester.tap(find.byKey(const Key('bayarForm.selesaikan')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Pilih label tujuan pembayaran'), findsOneWidget);
    expect(await db.select(db.transaksi).get(), isEmpty);

    await tester.tap(find.byKey(const Key('bayarForm.labelTujuan.Mandiri')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('bayarForm.selesaikan')));
    await tester.pumpAndSettle();

    expect(find.text('Pembayaran berhasil'), findsOneWidget);
    final pembayaran = (await db.select(db.pembayaran).get()).single;
    expect(jsonDecode(pembayaran.payloadGateway!)['label_tujuan'], 'Mandiri');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
