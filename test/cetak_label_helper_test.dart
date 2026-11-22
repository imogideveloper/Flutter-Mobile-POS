import 'dart:convert';

import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/core/printer/pengaturan_printer_providers.dart';
import 'package:apps_pos/core/printer/printer_service.dart';
import 'package:apps_pos/core/providers/database_provider.dart';
import 'package:apps_pos/core/struk/cetak_label_helper.dart';
import 'package:apps_pos/core/struk/cetak_struk_helper.dart';
import 'package:apps_pos/core/struk/penyusun_label_produk.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _PrinterUji implements PrinterService {
  _PrinterUji({this.bisaTersambung = true, this.bisaCetak = true});

  final bool bisaTersambung;
  final bool bisaCetak;
  bool tersambung = false;
  final urutan = <String>[];
  final terkirim = <String>[];

  @override
  Future<bool> izinDiberikan() async => true;
  @override
  Future<bool> mintaIzin() async => true;
  @override
  Future<bool> bluetoothAktif() async => true;
  @override
  Future<List<PerangkatBluetooth>> perangkatTerpasang() async => [];
  @override
  Future<bool> sambungkan(String macAddress) async {
    urutan.add('sambung:$macAddress');
    tersambung = bisaTersambung;
    return bisaTersambung;
  }

  @override
  Future<bool> statusTersambung() async => tersambung;
  @override
  Future<bool> cetakBytes(List<int> bytes) async {
    if (!bisaCetak) return false;
    terkirim.add(ascii.decode(bytes));
    return true;
  }

  @override
  Future<void> putuskan() async {
    urutan.add('putus');
    tersambung = false;
  }
}

void main() {
  final dua = [
    for (var i = 1; i <= 2; i++)
      LabelProdukData(namaProduk: 'Es Kopi Susu', urutan: i, total: 2, tanggalEpochMs: 1768000000000, nomorAntrean: 'A-001'),
  ];

  Future<WidgetRef> bangun(WidgetTester tester, AppDatabase db, PrinterService printer) async {
    WidgetRef? r;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWith((ref) => db),
        printerServiceProvider.overrideWithValue(printer),
      ],
      child: MaterialApp(
        home: Consumer(builder: (context, ref, _) {
          r = ref;
          return const SizedBox();
        }),
      ),
    ));
    return r!;
  }

  Future<void> tutup(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('printer label belum dipilih: status belum diatur, tidak ada yang tercetak', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final printer = _PrinterUji();
    final ref = await bangun(tester, db, printer);

    expect(await printerLabelTersedia(ref), isFalse);
    expect(await perluCetakLabelOtomatis(ref), isFalse);
    expect(await cetakLabelProduk(ref, dua), StatusCetak.printerBelumDiatur);
    expect(printer.terkirim, isEmpty);
    await tutup(tester);
  });

  testWidgets('mencetak satu perintah per stiker ke printer label lalu memutus koneksi', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.pengaturanPrinterDao.simpan(
      macAddress: 'AA:STRUK',
      lebarKertasMm: 58,
      cetakOtomatis: true,
      labelMacAddress: 'BB:LABEL',
      labelLebarMm: 50,
      labelTinggiMm: 30,
    );
    final printer = _PrinterUji()..tersambung = true; // masih tersambung ke printer struk
    final ref = await bangun(tester, db, printer);

    expect(await printerLabelTersedia(ref), isTrue);
    expect(await perluCetakLabelOtomatis(ref), isTrue);
    expect(await cetakLabelProduk(ref, dua), StatusCetak.berhasil);

    expect(printer.urutan, ['putus', 'sambung:BB:LABEL', 'putus'], reason: 'pindah dari printer struk, lalu lepas lagi');
    expect(printer.terkirim.length, 2);
    expect(printer.terkirim.first, startsWith('SIZE 50 mm,30 mm'));
    expect(printer.terkirim.first, contains('1/2'));
    expect(printer.terkirim.last, contains('2/2'));
    await tutup(tester);
  });

  testWidgets('gagal tersambung atau gagal cetak dilaporkan sebagai status, bukan exception', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.pengaturanPrinterDao.simpan(
      lebarKertasMm: 58,
      cetakOtomatis: true,
      labelMacAddress: 'BB:LABEL',
    );

    var ref = await bangun(tester, db, _PrinterUji(bisaTersambung: false));
    expect(await cetakLabelProduk(ref, dua), StatusCetak.gagalTersambung);

    final rusak = _PrinterUji(bisaCetak: false);
    ref = await bangun(tester, db, rusak);
    expect(await cetakLabelProduk(ref, dua), StatusCetak.gagalCetak);
    expect(rusak.urutan.last, 'putus', reason: 'koneksi tetap dilepas walau cetak gagal');
    await tutup(tester);
  });

  testWidgets('label otomatis bisa dimatikan walau printer label dipilih', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.pengaturanPrinterDao.simpan(
      lebarKertasMm: 58,
      cetakOtomatis: true,
      labelMacAddress: 'BB:LABEL',
      labelOtomatis: false,
    );
    final ref = await bangun(tester, db, _PrinterUji());
    expect(await printerLabelTersedia(ref), isTrue);
    expect(await perluCetakLabelOtomatis(ref), isFalse);
    await tutup(tester);
  });
}
