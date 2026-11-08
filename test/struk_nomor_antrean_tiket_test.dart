import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/features/fitur/presentation/providers/feature_gate_provider.dart';
import 'package:apps_pos/features/transaksi/domain/hasil_transaksi.dart';
import 'package:apps_pos/features/transaksi/domain/item_keranjang.dart';
import 'package:apps_pos/features/transaksi/presentation/pages/struk_page.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

/// Halaman sukses pembayaran: nomor antrian tampil besar, dan tombol cetak
/// tiket dapur hanya ada bila fitur `tiket_dapur` terbuka.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  HasilTransaksi hasil({String? nomorAntrean}) => HasilTransaksi(
        id: 'trx-1',
        nomorStruk: 'STR1',
        nomorAntrean: nomorAntrean,
        tanggal: DateTime(2026, 11, 9, 9, 30).toUtc().millisecondsSinceEpoch,
        items: const [
          ItemKeranjang(produkId: 'p1', namaProduk: 'Kopi Susu', hargaSatuan: 18000, qty: 2, lacakStok: false),
        ],
        subtotal: 36000,
        rincianPajak: const [],
        totalPajak: 0,
        total: 36000,
        totalBayar: 40000,
        kembalian: 4000,
      );

  Future<void> buka(WidgetTester tester, HasilTransaksi h, Set<String> fitur) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        ...overridesSudahLogin(db),
        featureGateProvider.overrideWith(
          (ref) async => FeatureGate(paket: 'Enterprise', kodeAktif: fitur, batas: const {}),
        ),
      ],
      child: MaterialApp(home: StrukPage(hasil: h)),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> tutup(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('nomor antrian tampil besar di bawah judul', (tester) async {
    await buka(tester, hasil(nomorAntrean: 'A-007'), {'nomor_antrean'});
    expect(find.byKey(const Key('strukPage.nomorAntrean')), findsOneWidget);
    expect(find.text('Antrian A-007'), findsOneWidget);
    await tutup(tester);
  });

  testWidgets('tanpa nomor antrian, kotak antrian tidak tampil', (tester) async {
    await buka(tester, hasil(), {});
    expect(find.byKey(const Key('strukPage.nomorAntrean')), findsNothing);
    await tutup(tester);
  });

  testWidgets('tombol Cetak tiket dapur tampil bila fitur tiket_dapur terbuka', (tester) async {
    await buka(tester, hasil(), {'tiket_dapur'});
    expect(find.byKey(const Key('strukPage.cetakTiketDapur')), findsOneWidget);
    expect(find.text('Cetak tiket dapur'), findsOneWidget);
    await tutup(tester);
  });

  testWidgets('tombol Cetak tiket dapur tidak ada bila fitur belum terbuka', (tester) async {
    await buka(tester, hasil(), {'pos'});
    expect(find.byKey(const Key('strukPage.cetakTiketDapur')), findsNothing);
    await tutup(tester);
  });

  testWidgets('menekan Cetak tiket dapur tanpa printer terhubung memberi tahu pengguna', (tester) async {
    await buka(tester, hasil(), {'tiket_dapur'});
    await tester.tap(find.byKey(const Key('strukPage.cetakTiketDapur')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Printer belum diatur'), findsOneWidget);
    await tutup(tester);
  });
}
