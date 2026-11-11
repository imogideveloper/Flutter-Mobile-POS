import 'package:apps_pos/core/providers/izin_provider.dart';
import 'package:apps_pos/core/router/app_shell.dart';
import 'package:apps_pos/core/widgets/izin_guard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Set<String> izin) => ProviderScope(
      overrides: [izinSayaProvider.overrideWith((ref) async => izin)],
      child: const MaterialApp(
        home: IzinGuard(kodeIzin: 'pengguna.kelola', child: Scaffold(body: Text('ISI RAHASIA'))),
      ),
    );

void main() {
  testWidgets('IzinGuard menampilkan isi bila izin ada', (tester) async {
    await tester.pumpWidget(_app({'pengguna.kelola'}));
    await tester.pumpAndSettle();
    expect(find.text('ISI RAHASIA'), findsOneWidget);
  });

  testWidgets('IzinGuard menolak (pesan, bukan isi) bila izin tidak ada', (tester) async {
    await tester.pumpWidget(_app({'transaksi.buat'}));
    await tester.pumpAndSettle();
    expect(find.text('ISI RAHASIA'), findsNothing);
    expect(find.text('Tidak ada akses'), findsOneWidget);
  });

  test('tab Produk/Laporan tersembunyi untuk kasir, tampil untuk owner', () {
    expect(tabTersembunyi({'transaksi.buat', 'shift.buka_tutup'}), {tabProduk, tabLaporan});
    expect(tabTersembunyi({'produk.kelola'}), {tabLaporan});
    expect(tabTersembunyi({'produk.kelola', 'laporan.lihat'}), isEmpty);
    expect(tabTersembunyi(const {}), {tabProduk, tabLaporan});
  });
}
