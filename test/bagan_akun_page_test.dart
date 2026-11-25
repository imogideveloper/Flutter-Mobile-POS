import 'package:apps_pos/core/network/auth_session_store.dart';
import 'package:apps_pos/core/network/backend_api.dart';
import 'package:apps_pos/core/network/dio_backend_api.dart';
import 'package:apps_pos/features/pengeluaran/presentation/pages/bagan_akun_page.dart';
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
  @override
  Future<dynamic> getJson({required String accessToken, required String path, Map<String, dynamic>? query}) async {
    expect(path, '/akuntansi/coa');
    return {
      'akun': [
        {'kode': '1-1100', 'nama': 'Kas', 'kelompok': 'aset', 'saldo_normal': 'debit'},
        {'kode': '6-1100', 'nama': 'Beban sewa', 'kelompok': 'beban', 'saldo_normal': 'debit'},
      ],
      'pemetaan_pengeluaran': [
        {'kategori': 'sewa', 'kode_akun': '6-1100'},
      ],
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('Bagan akun menampilkan akun per kelompok dan akun untuk kategori pengeluaran', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        backendApiProvider.overrideWithValue(_Api()),
        authSessionStoreProvider.overrideWithValue(_Sesi()),
      ],
      child: const MaterialApp(home: BaganAkunPage()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Aset'), findsOneWidget);
    expect(find.text('Beban usaha'), findsOneWidget);
    expect(find.text('Kas'), findsOneWidget);
    expect(find.text('Sewa'), findsOneWidget, reason: 'label kategori pengeluaran');
    expect(find.text('6-1100 Beban sewa'), findsOneWidget, reason: 'akun untuk kategori sewa');
  });
}
