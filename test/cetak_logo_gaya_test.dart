import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/core/printer/printer_service.dart';
import 'package:apps_pos/core/providers/database_provider.dart';
import 'package:apps_pos/core/providers/toko_profile_provider.dart';
import 'package:apps_pos/core/struk/cetak_struk_helper.dart';
import 'package:apps_pos/core/struk/gaya_logo.dart';
import 'package:apps_pos/core/struk/penyusun_struk.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Printer palsu yang merekam bytes terakhir yang dicetak.
class _PrinterRekam implements PrinterService {
  List<int>? bytes;

  @override
  Future<bool> izinDiberikan() async => true;
  @override
  Future<bool> mintaIzin() async => true;
  @override
  Future<bool> bluetoothAktif() async => true;
  @override
  Future<List<PerangkatBluetooth>> perangkatTerpasang() async => [];
  @override
  Future<bool> sambungkan(String macAddress) async => true;
  @override
  Future<bool> statusTersambung() async => true;
  @override
  Future<bool> cetakBytes(List<int> data) async {
    bytes = data;
    return true;
  }

  @override
  Future<void> putuskan() async {}
}

void main() {
  const baris = [BarisStruk('Tes cetak')];

  testWidgets('logo gaya otomatis ikut tercetak dari nama usaha; gaya berbeda menghasilkan cetakan berbeda', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.pengaturanPrinterDao.simpan(
      macAddress: '00:11:22:33:44:55',
      namaPrinter: 'Printer Tes',
      lebarKertasMm: 58,
      cetakOtomatis: false,
    );
    final printer = _PrinterRekam();

    WidgetRef? ref;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWith((r) => db),
        printerServiceProvider.overrideWithValue(printer),
        tokoProfileProvider.overrideWith((r) async => const TokoProfile(
              namaToko: 'Kopi Senja',
              jenisUsaha: JenisUsaha.kafe,
              namaPemilik: 'Rina',
            )),
      ],
      child: MaterialApp(
        home: Consumer(builder: (context, r, _) {
          ref = r;
          return const SizedBox();
        }),
      ),
    ));

    Future<List<int>> cetak({required bool logo, GayaLogo gaya = GayaLogo.unggah}) async {
      printer.bytes = null;
      final status = await tester.runAsync(() => cetakStruk(ref!, baris, tampilkanLogo: logo, gayaLogo: gaya));
      expect(status, StatusCetak.berhasil);
      return printer.bytes!;
    }

    final tanpaLogo = await cetak(logo: false, gaya: GayaLogo.lingkaran);
    final lingkaran = await cetak(logo: true, gaya: GayaLogo.lingkaran);
    final cincin = await cetak(logo: true, gaya: GayaLogo.cincin);
    final inisial = await cetak(logo: true, gaya: GayaLogo.inisial);

    expect(lingkaran.length, greaterThan(tanpaLogo.length), reason: 'logo raster ikut dikirim ke printer');
    expect(cincin, isNot(equals(lingkaran)));
    expect(inisial, isNot(equals(lingkaran)));
    expect(inisial, isNot(equals(cincin)));

    // "Tanpa logo" = saklar logo mati: gaya apa pun tidak mencetak logo.
    final matiDenganGaya = await cetak(logo: false, gaya: GayaLogo.cincin);
    expect(matiDenganGaya, tanpaLogo);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
