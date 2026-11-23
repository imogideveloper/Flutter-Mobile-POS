import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/features/auth/presentation/pages/pengguna_form_page.dart';
import 'package:apps_pos/features/pelanggan/presentation/pages/pelanggan_form_page.dart';
import 'package:apps_pos/features/produk/presentation/pages/kategori_form_page.dart';
import 'package:apps_pos/features/produk/presentation/pages/produk_form_page.dart';
import 'package:apps_pos/features/promo/presentation/pages/pajak_form_page.dart';
import 'package:apps_pos/features/promo/presentation/pages/promo_form_page.dart';
import 'package:apps_pos/features/shift/presentation/pages/buka_shift_form_page.dart';
import 'package:apps_pos/features/shift/presentation/pages/catat_kas_form_page.dart';
import 'package:apps_pos/features/shift/presentation/pages/tutup_shift_form_page.dart';
import 'package:apps_pos/features/stok/presentation/pages/stok_mutasi_form_page.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

/// Jaring pengaman tampilan: setiap formulir yang bisa dibuka tanpa server tidak boleh punya kolom yang menempel.
/// Formulir yang butuh server atau argumen khusus dicakup oleh pemeriksa statis (jarak_antar_kolom_statis_test).
void main() {
  final formulir = <String, Widget Function()>{
    'Produk': () => const ProdukFormPage(),
    'Pelanggan': () => const PelangganFormPage(),
    'Kategori': () => const KategoriFormPage(),
    'Promo': () => const PromoFormPage(),
    'Pajak': () => const PajakFormPage(),
    'Pengguna': () => const PenggunaFormPage(),
    'Buka shift': () => const BukaShiftFormPage(),
    'Catat kas': () => const CatatKasFormPage(shiftId: 'shift-uji'),
    'Tutup shift': () => const TutupShiftFormPage(shiftId: 'shift-uji'),
    'Mutasi stok': () => const StokMutasiFormPage(),
  };

  for (final entri in formulir.entries) {
    testWidgets('formulir ${entri.key}: kolom berjarak', (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      tester.view.physicalSize = const Size(900, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(ProviderScope(
        overrides: overridesSudahLogin(db),
        child: MaterialApp(home: entri.value()),
      ));
      await tester.pumpAndSettle();

      pastikanKolomBerjarak(tester);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 1));
    });
  }
}
