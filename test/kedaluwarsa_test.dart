import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/features/produk/data/local/tables/produk_table.dart';
import 'package:apps_pos/features/stok/domain/kedaluwarsa.dart';
import 'package:apps_pos/features/stok/presentation/pages/kedaluwarsa_page.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'test_helpers.dart';

int _tgl(int y, int m, int d) => DateTime.utc(y, m, d).millisecondsSinceEpoch;

void main() {
  group('logika kedaluwarsa', () {
    final hariIni = DateTime(2026, 11, 16, 15, 30);

    test('sisaHariKedaluwarsa menghitung hari kalender, bukan jam', () {
      expect(sisaHariKedaluwarsa(_tgl(2026, 11, 16), hariIni), 0);
      expect(sisaHariKedaluwarsa(_tgl(2026, 11, 17), hariIni), 1);
      expect(sisaHariKedaluwarsa(_tgl(2026, 11, 15), hariIni), -1);
      expect(sisaHariKedaluwarsa(_tgl(2026, 12, 16), hariIni), 30);
    });

    test('statusKedaluwarsa: lewat, segera (sampai ambang termasuk hari ini), aman', () {
      StatusKedaluwarsa s(int ms, {int ingatkan = 30}) =>
          statusKedaluwarsa(tanggalKedaluwarsaMs: ms, ingatkanHari: ingatkan, sekarang: hariIni);
      expect(s(_tgl(2026, 11, 15)), StatusKedaluwarsa.sudahLewat);
      expect(s(_tgl(2026, 11, 16)), StatusKedaluwarsa.segera, reason: 'hari ini belum lewat');
      expect(s(_tgl(2026, 12, 16)), StatusKedaluwarsa.segera, reason: 'tepat 30 hari lagi');
      expect(s(_tgl(2026, 12, 17)), StatusKedaluwarsa.aman);
      expect(s(_tgl(2026, 11, 17), ingatkan: 0), StatusKedaluwarsa.aman);
    });

    test('labelSisaHari', () {
      expect(labelSisaHari(-3), 'Lewat 3 hari');
      expect(labelSisaHari(0), 'Kedaluwarsa hari ini');
      expect(labelSisaHari(5), '5 hari lagi');
    });
  });

  testWidgets('halaman menampilkan batch urut kedaluwarsa dengan penanda, dan yang dihapus tidak tampil', (tester) async {
    await initializeDateFormatting('id_ID');
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.fiturDao.simpanStatusFitur(
      tokoId: 'toko-default',
      paket: 'Enterprise',
      kodeFiturAktif: const ['pengingat_kedaluwarsa'],
      batasPerKode: const {},
      updatedAt: 0,
    );
    await db.produkDao.upsertProduk(ProdukCompanion.insert(
      id: 'susu',
      tokoId: 'toko-default',
      nama: 'Susu UHT',
      tipe: ProdukTipe.barang,
      createdAt: 0,
      updatedAt: 0,
    ));

    Future<void> batch(String id, int ms, {String? nomor, int? hapus}) => db.stokDao.upsertBatchDariSync(
          id: id,
          outletId: 'outlet-default',
          produkId: 'susu',
          nomorBatch: nomor,
          tanggalKedaluwarsa: ms,
          qtyAwal: 10,
          qtySisa: 8,
          ingatkanHari: 30,
          updatedAt: 1,
          deletedAt: hapus,
        );

    final sekarang = DateTime(2026, 11, 16);
    await batch('lewat', _tgl(2026, 11, 10), nomor: 'A1');
    await batch('segera', _tgl(2026, 11, 25));
    await batch('aman', _tgl(2027, 6, 1), nomor: 'C3');
    await batch('dihapus', _tgl(2026, 11, 20), hapus: 5);

    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: overridesSudahLogin(db),
      child: MaterialApp(home: KedaluwarsaPage(sekarang: sekarang)),
    ));
    await tester.pumpAndSettle();

    String teks(String kunci) => tester.widget<Text>(find.byKey(Key(kunci))).data!;
    expect(teks('kedaluwarsa.lewat'), '1');
    expect(teks('kedaluwarsa.segera'), '1');
    expect(teks('kedaluwarsa.semua'), '3');
    expect(find.byKey(const Key('kedaluwarsa.baris.dihapus')), findsNothing);
    expect(teks('kedaluwarsa.status.lewat'), contains('Lewat 6 hari'));
    expect(teks('kedaluwarsa.status.segera'), contains('9 hari lagi'));
    expect(find.text('Batch A1 · 8 unit'), findsOneWidget);
    expect(find.text('Tanpa nomor batch · 8 unit'), findsOneWidget);

    final y = (String k) => tester.getTopLeft(find.byKey(Key(k))).dy;
    expect(y('kedaluwarsa.baris.lewat') < y('kedaluwarsa.baris.segera'), isTrue, reason: 'terdekat lebih dulu');
    expect(y('kedaluwarsa.baris.segera') < y('kedaluwarsa.baris.aman'), isTrue);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('tombol catat batch terkunci bila paket belum membuka fitur', (tester) async {
    await initializeDateFormatting('id_ID');
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.fiturDao.simpanStatusFitur(
      tokoId: 'toko-default',
      paket: 'Gratis',
      kodeFiturAktif: const [],
      batasPerKode: const {},
      updatedAt: 0,
    );
    await tester.pumpWidget(ProviderScope(
      overrides: overridesSudahLogin(db),
      child: const MaterialApp(home: KedaluwarsaPage()),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('fiturTerkunci.pengingat_kedaluwarsa')), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
