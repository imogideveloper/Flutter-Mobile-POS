import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/features/laporan/data/laporan_repository.dart' show PeriodeLaporan;
import 'package:apps_pos/features/laporan/presentation/providers/laporan_providers.dart';
import 'package:apps_pos/features/produk/data/local/tables/produk_table.dart' hide Produk;
import 'package:apps_pos/features/stok/data/local/tables/mutasi_stok_table.dart' show MutasiJenis;
import 'package:apps_pos/main.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'test_helpers.dart';

/// Regresi utk bug nyata yang dilaporkan pengguna: layar Laporan jadi
/// blank/abu-abu kosong tepat sesudah memilih & menyimpan rentang tanggal
/// custom ("Atur"). Akar masalah: app TIDAK PERNAH memanggil
/// initializeDateFormatting() (lihat main.dart), padahal `_TabPeriode` di
/// laporan_page.dart memformat label rentang custom pakai
/// `DateFormat('d MMM', 'id_ID')` - locale 'id_ID' dgn nama bulan WAJIB
/// data locale ter-load dulu, kalau tidak `intl` melempar
/// LocaleDataException saat widget itu di-build. Di release build,
/// exception saat build dirender sbg kotak abu-abu kosong (ErrorWidget
/// default Flutter), persis laporan pengguna "blank gak ada apa-apa".
///
/// Widget test TIDAK lewat main() (pumpWidget langsung konstruksi
/// AppsPosApp), jadi initializeDateFormatting() dipanggil manual di sini
/// jg - membuktikan baris yang sama persis di main.dart itu yang
/// memperbaikinya.
void main() {
  testWidgets('layar Laporan tidak crash saat periode=custom dgn rentang tanggal terisi',
      (tester) async {
    await initializeDateFormatting('id_ID');

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await db.produkDao.upsertProduk(ProdukCompanion.insert(
      id: 'p1',
      tokoId: 'toko-default',
      nama: 'Kopi Hitam',
      tipe: ProdukTipe.barang,
      hargaJual: const Value(15000),
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

    final now = DateTime.now();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        ...overridesSudahLogin(db),
        // Simulasikan persis kondisi tepat SESUDAH pengguna memilih &
        // menyimpan rentang custom lewat dialog "Atur".
        periodeLaporanProvider.overrideWith((ref) => PeriodeLaporan.custom),
        rentangCustomLaporanProvider.overrideWith(
          (ref) => (now.subtract(const Duration(days: 3)), now),
        ),
      ],
      child: const AppsPosApp(),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Laporan'));
    await tester.pumpAndSettle();

    // Label "Atur" harus berubah jadi rentang tanggal (format 'd MMM'
    // id_ID, mis. "10 Okt-13 Okt") TANPA melempar exception apa pun.
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('laporanForm.atur')), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
