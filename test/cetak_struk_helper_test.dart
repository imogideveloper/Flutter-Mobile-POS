import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/core/printer/printer_service.dart';
import 'package:apps_pos/core/providers/database_provider.dart';
import 'package:apps_pos/core/struk/cetak_struk_helper.dart';
import 'package:apps_pos/core/struk/penyusun_struk.dart';
import 'package:apps_pos/features/produk/data/local/tables/produk_table.dart'
    hide Produk;
import 'package:apps_pos/features/stok/data/local/tables/mutasi_stok_table.dart'
    show MutasiJenis;
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Printer yang SELALU gagal tersambung - mensimulasikan printer mati/putus
/// (tahap 4 bagian D.3).
class _PrinterGagalTersambung implements PrinterService {
  @override
  Future<bool> izinDiberikan() async => true;
  @override
  Future<bool> mintaIzin() async => true;
  @override
  Future<bool> bluetoothAktif() async => true;
  @override
  Future<List<PerangkatBluetooth>> perangkatTerpasang() async => [];
  @override
  Future<bool> sambungkan(String macAddress) async => false;
  @override
  Future<bool> statusTersambung() async => false;
  @override
  Future<bool> cetakBytes(List<int> bytes) async => false;
  @override
  Future<void> putuskan() async {}
}

void main() {
  const barisTes = [BarisStruk('Tes cetak')];

  Future<WidgetRef> bangunRef(
    WidgetTester tester, {
    required AppDatabase db,
    required PrinterService printer,
  }) async {
    WidgetRef? refDitangkap;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWith((ref) => db),
          printerServiceProvider.overrideWithValue(printer),
        ],
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) {
              refDitangkap = ref;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    return refDitangkap!;
  }

  testWidgets('printer belum diatur: cetakStruk balikkan status tanpa exception', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final ref = await bangunRef(tester, db: db, printer: _PrinterGagalTersambung());
    final status = await cetakStruk(ref, barisTes);
    expect(status, StatusCetak.printerBelumDiatur);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets(
      'printer tersimpan tapi gagal tersambung: status gagal, TIDAK melempar exception, transaksi tetap tersimpan',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    // Seed transaksi "sudah tersimpan" langsung via DAO (mensimulasikan
    // transaksi yg sudah berhasil di-checkout SEBELUM percobaan cetak).
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
    await db.pengaturanPrinterDao.simpan(
      macAddress: '00:11:22:33:44:55',
      namaPrinter: 'Printer Tes',
      lebarKertasMm: 58,
      cetakOtomatis: true,
    );

    final ref = await bangunRef(tester, db: db, printer: _PrinterGagalTersambung());
    final statusTersambungGagal = await cetakStruk(ref, barisTes);
    expect(statusTersambungGagal, StatusCetak.gagalTersambung);

    final stokRow = await (db.select(db.stok)
          ..where((t) => t.outletId.equals('outlet-default') & t.produkId.equals('p1')))
        .getSingle();
    expect(stokRow.jumlah, 10); // tidak terganggu sama sekali oleh percobaan cetak

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('perluCetakOtomatis mengikuti baris pengaturan tersimpan', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final ref = await bangunRef(tester, db: db, printer: _PrinterGagalTersambung());
    expect(await perluCetakOtomatis(ref), isFalse); // belum ada pengaturan sama sekali

    await db.pengaturanPrinterDao.simpan(
      macAddress: '00:11:22:33:44:55',
      namaPrinter: 'Printer Tes',
      lebarKertasMm: 58,
      cetakOtomatis: false,
    );
    expect(await perluCetakOtomatis(ref), isFalse); // cetakOtomatis dimatikan

    await db.pengaturanPrinterDao.simpan(
      macAddress: '00:11:22:33:44:55',
      namaPrinter: 'Printer Tes',
      lebarKertasMm: 58,
      cetakOtomatis: true,
    );
    expect(await perluCetakOtomatis(ref), isTrue);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
