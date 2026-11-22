import 'package:apps_pos/core/network/auth_session_store.dart';
import 'package:apps_pos/core/network/backend_api.dart';
import 'package:apps_pos/core/network/connectivity_provider.dart';
import 'package:apps_pos/core/network/dio_backend_api.dart';
import 'package:apps_pos/core/providers/izin_provider.dart';
import 'package:apps_pos/features/auth/presentation/pages/peran_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

Widget _bungkus(Widget child) => MaterialApp.router(
      routerConfig: GoRouter(
        initialLocation: '/form',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const Scaffold(body: SizedBox()),
            routes: [GoRoute(path: 'form', builder: (context, state) => child)],
          ),
        ],
      ),
    );

class _Sesi extends AuthSessionStore {
  _Sesi() : super(const FlutterSecureStorage());

  @override
  Future<SesiBackend?> muat() async => const SesiBackend(
        accessToken: 't',
        refreshToken: 'r',
        tokoId: 'toko-1',
        outletId: 'outlet-1',
        penggunaId: 'p-1',
        perangkatId: 'perangkat-1',
      );
}

class _Api implements BackendApi {
  String? path;
  Map<String, dynamic>? body;
  String? dihapus;

  @override
  Future<dynamic> getJson({required String accessToken, required String path, Map<String, dynamic>? query}) async {
    if (path == '/izin') {
      return [
        {'kode': 'transaksi.buat', 'modul': 'penjualan', 'deskripsi': 'Membuat transaksi'},
        {'kode': 'bon.jual', 'modul': 'penjualan', 'deskripsi': 'Jual bon'},
        {'kode': 'pengaturan.kelola', 'modul': 'pengaturan', 'deskripsi': 'Pengaturan'},
      ];
    }
    if (path == '/roles/bawaan') {
      return {'id': 'bawaan', 'nama': 'Kasir', 'is_system': true, 'izin_kode': ['transaksi.buat'], 'jumlah_pengguna': 2};
    }
    if (path == '/roles/buatan') {
      return {'id': 'buatan', 'nama': 'Pelayan', 'is_system': false, 'izin_kode': ['transaksi.buat'], 'jumlah_pengguna': 0};
    }
    return <dynamic>[];
  }

  @override
  Future<dynamic> postJson({required String accessToken, required String path, Map<String, dynamic>? body}) async {
    this.path = path;
    this.body = body;
    return {};
  }

  @override
  Future<dynamic> patchJson({required String accessToken, required String path, required Map<String, dynamic> body}) async {
    this.path = path;
    this.body = body;
    return {};
  }

  @override
  Future<void> deleteJson({required String accessToken, required String path}) async {
    dihapus = path;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Future<_Api> _tampil(WidgetTester tester, Widget halaman, {Set<String>? izinSaya}) async {
  final api = _Api();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      authSessionStoreProvider.overrideWithValue(_Sesi()),
      backendApiProvider.overrideWithValue(api),
      isOnlineProvider.overrideWith((ref) => Stream.value(true)),
      izinSayaProvider.overrideWith((ref) async => izinSaya ?? {'transaksi.buat', 'bon.jual', 'pengaturan.kelola'}),
    ],
    child: _bungkus(halaman),
  ));
  await tester.pumpAndSettle();
  return api;
}

Future<void> _tutup(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 1));
}

void main() {
  testWidgets('peran baru: isi nama, centang hak akses, simpan terkirim ke server', (tester) async {
    final api = await _tampil(tester, const PeranFormPage());

    expect(find.text('Jualan di Kasir'), findsOneWidget);
    expect(find.text('Jual bon / DP'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('peranForm.nama')), 'Supervisor');
    await tester.tap(find.byKey(const Key('peranForm.izin.bon.jual')));
    await tester.tap(find.byKey(const Key('peranForm.izin.transaksi.buat')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('peranForm.simpan')));
    await tester.tap(find.byKey(const Key('peranForm.simpan')));
    await tester.pumpAndSettle();

    expect(api.path, '/roles');
    expect(api.body!['nama'], 'Supervisor');
    expect(api.body!['izin_kode'], ['bon.jual', 'transaksi.buat']);
    await _tutup(tester);
  });

  testWidgets('nama kosong ditolak tanpa memanggil server', (tester) async {
    final api = await _tampil(tester, const PeranFormPage());
    await tester.ensureVisible(find.byKey(const Key('peranForm.simpan')));
    await tester.tap(find.byKey(const Key('peranForm.simpan')));
    await tester.pump();
    expect(api.path, isNull);
    expect(find.text('Nama peran wajib diisi'), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
    await _tutup(tester);
  });

  testWidgets('peran bawaan hanya bisa dilihat: tanpa tombol simpan dan hapus', (tester) async {
    await _tampil(tester, const PeranFormPage(peranId: 'bawaan'));
    expect(find.text('Peran bawaan'), findsOneWidget);
    expect(find.byKey(const Key('peranForm.simpan')), findsNothing);
    expect(find.byKey(const Key('peranForm.hapus')), findsNothing);
    final cb = tester.widget<CheckboxListTile>(find.byKey(const Key('peranForm.izin.transaksi.buat')));
    expect(cb.value, isTrue);
    expect(cb.onChanged, isNull);
    await _tutup(tester);
  });

  testWidgets('izin yang tidak dimiliki pelaku tidak bisa dicentang', (tester) async {
    await _tampil(tester, const PeranFormPage(), izinSaya: {'transaksi.buat'});
    final dimiliki = tester.widget<CheckboxListTile>(find.byKey(const Key('peranForm.izin.transaksi.buat')));
    final tidak = tester.widget<CheckboxListTile>(find.byKey(const Key('peranForm.izin.pengaturan.kelola')));
    expect(dimiliki.onChanged, isNotNull);
    expect(tidak.onChanged, isNull);
    await _tutup(tester);
  });

  testWidgets('peran buatan: ubah lalu simpan memakai PATCH, hapus memanggil DELETE', (tester) async {
    final api = await _tampil(tester, const PeranFormPage(peranId: 'buatan'));
    expect(find.text('Ubah peran'), findsOneWidget);

    await tester.tap(find.byKey(const Key('peranForm.izin.bon.jual')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('peranForm.simpan')));
    await tester.tap(find.byKey(const Key('peranForm.simpan')));
    await tester.pumpAndSettle();
    expect(api.path, '/roles/buatan');
    expect(api.body!['izin_kode'], ['bon.jual', 'transaksi.buat']);
    await _tutup(tester);

    final api2 = await _tampil(tester, const PeranFormPage(peranId: 'buatan'));
    await tester.ensureVisible(find.byKey(const Key('peranForm.hapus')));
    await tester.tap(find.byKey(const Key('peranForm.hapus')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('peranForm.hapusYa')));
    await tester.pumpAndSettle();
    expect(api2.dihapus, '/roles/buatan');
    await _tutup(tester);
  });
}
