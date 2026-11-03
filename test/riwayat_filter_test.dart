import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/features/transaksi/data/local/tables/transaksi_table.dart';
import 'package:apps_pos/main.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

/// F3.B - preset filter tanggal di RiwayatListPage: transaksi di luar
/// rentang "Hari ini" (default) tidak boleh tampil, tapi muncul lagi
/// begitu preset "30 hari" dipilih.
void main() {
  testWidgets('filter preset Hari ini vs 30 hari', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final sekarang = DateTime.now().toUtc();
    final sepuluhHariLalu = sekarang.subtract(const Duration(days: 10));

    Future<void> tambahTransaksi(String id, String nomorStruk, DateTime tanggal) {
      return db.into(db.transaksi).insert(TransaksiCompanion.insert(
            id: id,
            tokoId: 'toko-default',
            outletId: 'outlet-default',
            penggunaId: 'pengguna-default',
            nomorStruk: nomorStruk,
            tanggal: tanggal.millisecondsSinceEpoch,
            status: TransaksiStatus.selesai,
            total: const Value(15000),
            totalBayar: const Value(15000),
            createdAt: tanggal.millisecondsSinceEpoch,
            updatedAt: tanggal.millisecondsSinceEpoch,
          ));
    }

    await tambahTransaksi('t-baru', 'OUT1-BARU', sekarang);
    await tambahTransaksi('t-lama', 'OUT1-LAMA', sepuluhHariLalu);

    await tester.pumpWidget(ProviderScope(
      overrides: overridesSudahLogin(db),
      child: const AppsPosApp(),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Riwayat').first);
    await tester.pumpAndSettle();

    // Default "Hari ini" - cuma transaksi baru yang tampil.
    expect(find.text('#OUT1-BARU'), findsOneWidget);
    expect(find.text('#OUT1-LAMA'), findsNothing);

    await tester.tap(find.byKey(const Key('riwayatForm.filterTanggal')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('30 hari'));
    await tester.pumpAndSettle();

    // Preset "30 hari" - keduanya tampil (percobaan ambil dari server boleh
    // gagal di lingkungan test, tapi data lokal tetap jadi sumber tampilan
    // fallback - lihat _cobaAmbilDariServer).
    expect(find.text('#OUT1-BARU'), findsOneWidget);
    expect(find.text('#OUT1-LAMA'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
