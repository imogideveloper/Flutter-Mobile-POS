import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/core/network/auth_session_store.dart';
import 'package:apps_pos/core/providers/session_provider.dart';
import 'package:apps_pos/features/outlet/presentation/pages/ganti_outlet_page.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

class _StoreRekam extends AuthSessionStore {
  _StoreRekam() : super(const FlutterSecureStorage());

  final outletDisimpan = <String>[];

  @override
  Future<SesiBackend?> muat() async => null;

  @override
  Future<void> simpanOutletAktif(String outletId) async => outletDisimpan.add(outletId);
}

final _daftar = [
  const OutletPilihan(id: outletIdPlaceholder, nama: 'Outlet Pusat', kode: 'OUT1'),
  const OutletPilihan(id: 'o2', nama: 'Outlet Cabang', kode: 'OUT2', alamat: 'Jl. Mawar 1'),
];

void main() {
  testWidgets('menandai outlet aktif; memilih outlet lain meminta konfirmasi lalu menyimpan dan mengganti provider',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final store = _StoreRekam();

    await tester.pumpWidget(ProviderScope(
      overrides: [
        ...overridesSudahLogin(db).where((o) => o.toString().contains('AuthSessionStore') == false),
        authSessionStoreProvider.overrideWithValue(store),
        outletSayaProvider.overrideWith((ref) async => _daftar),
      ],
      child: const MaterialApp(home: GantiOutletPage()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Outlet Pusat'), findsOneWidget);
    expect(find.text('OUT2 · Jl. Mawar 1'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget, reason: 'hanya outlet aktif yang bertanda');

    // Mengetuk outlet yang sedang aktif tidak melakukan apa pun.
    await tester.tap(find.text('Outlet Pusat'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('gantiOutlet.ya')), findsNothing);

    await tester.tap(find.text('Outlet Cabang'));
    await tester.pumpAndSettle();
    expect(find.text('Pindah ke Outlet Cabang?'), findsOneWidget);
    await tester.tap(find.text('Batal'));
    await tester.pumpAndSettle();
    expect(store.outletDisimpan, isEmpty, reason: 'batal tidak mengganti outlet');

    await tester.tap(find.text('Outlet Cabang'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('gantiOutlet.ya')));
    await tester.pumpAndSettle();
    expect(store.outletDisimpan, ['o2']);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('shift masih terbuka di outlet sekarang: pindah outlet ditolak tanpa dialog', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final store = _StoreRekam();
    await db.shiftDao.bukaShift(
      id: 'sh1',
      tokoId: tokoIdPlaceholder,
      outletId: outletIdPlaceholder,
      penggunaId: 'pengguna-1',
      modalAwal: 0,
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        ...overridesSudahLogin(db).where((o) => o.toString().contains('AuthSessionStore') == false),
        authSessionStoreProvider.overrideWithValue(store),
        outletSayaProvider.overrideWith((ref) async => _daftar),
      ],
      child: const MaterialApp(home: Scaffold(body: GantiOutletPage())),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Outlet Cabang'));
    await tester.pumpAndSettle();
    expect(find.text('Tutup shift di outlet ini dulu sebelum pindah outlet.'), findsOneWidget);
    expect(find.byKey(const Key('gantiOutlet.ya')), findsNothing);
    expect(store.outletDisimpan, isEmpty);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
