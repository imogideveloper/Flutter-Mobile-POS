import 'package:apps_pos/core/network/auth_session_store.dart';
import 'package:apps_pos/core/network/backend_api.dart';
import 'package:apps_pos/core/network/dio_backend_api.dart';
import 'package:apps_pos/features/pelanggan/domain/pelanggan.dart';
import 'package:apps_pos/features/pelanggan/presentation/pages/deposit_page.dart';
import 'package:apps_pos/features/pelanggan/presentation/providers/pelanggan_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _Sesi extends AuthSessionStore {
  _Sesi() : super(const FlutterSecureStorage());

  @override
  Future<SesiBackend?> muat() async => const SesiBackend(
        accessToken: 't',
        refreshToken: 'r',
        tokoId: 'toko',
        outletId: 'outlet',
        penggunaId: 'u',
        perangkatId: 'p',
      );
}

class _Api implements BackendApi {
  final List<Map<String, dynamic>> kiriman = [];

  @override
  Future<dynamic> getJson({required String accessToken, required String path, Map<String, dynamic>? query}) async {
    if (path == '/deposit/pelanggan/p2') {
      return {
        'pelanggan_id': 'p2',
        'nama': 'Budi',
        'saldo': '700000.00',
        'riwayat': [
          {'id': 'm2', 'jenis': 'pakai', 'jumlah': '50000.00', 'catatan': 'Ngopi', 'dibuat': '2026-11-17T10:00:00+00:00'},
          {'id': 'm1', 'jenis': 'topup', 'jumlah': '750000.00', 'catatan': null, 'dibuat': '2026-11-16T09:00:00+00:00'},
        ],
      };
    }
    expect(path, '/deposit/ringkasan');
    return {
      'total_saldo': '1000000.00',
      'jumlah_pelanggan': 2,
      'pelanggan': [
        {'pelanggan_id': 'p2', 'nama': 'Budi', 'saldo': '700000.00'},
        {'pelanggan_id': 'p1', 'nama': 'Ani', 'saldo': '300000.00'},
      ],
    };
  }

  @override
  Future<dynamic> postJson({required String accessToken, required String path, Map<String, dynamic>? body}) async {
    expect(path, '/deposit');
    kiriman.add(body!);
    return {};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Pelanggan _p(String id, String nama) =>
    Pelanggan(id: id, tokoId: 't', nama: nama, poin: 0, totalBelanja: 0);

void main() {
  testWidgets('menampilkan total dan saldo, lalu mencatat top-up untuk pelanggan yang dipilih', (tester) async {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final api = _Api();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        backendApiProvider.overrideWithValue(api),
        authSessionStoreProvider.overrideWithValue(_Sesi()),
        pelangganAktifProvider.overrideWith((ref) => Stream.value([_p('p1', 'Ani'), _p('p2', 'Budi')])),
      ],
      child: const MaterialApp(home: DepositPage()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Rp 1.000.000'), findsOneWidget);
    expect(find.text('Rp 700.000'), findsOneWidget);

    await tester.tap(find.byKey(const Key('deposit.riwayat.p2')));
    await tester.pumpAndSettle();
    expect(find.text('+Rp 750.000'), findsOneWidget);
    expect(find.text('-Rp 50.000'), findsOneWidget);
    expect(find.text('2026-11-17 - Ngopi'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('deposit.baris.p2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('deposit.simpan')));
    await tester.pump();
    expect(find.byKey(const Key('deposit.salah')), findsOneWidget);
    expect(api.kiriman, isEmpty);

    await tester.enterText(find.byKey(const Key('deposit.jumlah')), '250000');
    await tester.tap(find.byKey(const Key('deposit.simpan')));
    await tester.pumpAndSettle();
    expect(api.kiriman.single, {'pelanggan_id': 'p2', 'jenis': 'topup', 'jumlah': '250000'});

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
