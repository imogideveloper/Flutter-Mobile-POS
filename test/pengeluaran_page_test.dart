import 'package:apps_pos/core/network/auth_session_store.dart';
import 'package:apps_pos/core/network/backend_api.dart';
import 'package:apps_pos/core/network/backend_exception.dart';
import 'package:apps_pos/core/network/dio_backend_api.dart';
import 'package:apps_pos/features/pengeluaran/domain/pengeluaran.dart';
import 'package:apps_pos/features/pengeluaran/presentation/pages/pengeluaran_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

class _Sesi extends AuthSessionStore {
  _Sesi() : super(const FlutterSecureStorage());

  @override
  Future<SesiBackend?> muat() async => const SesiBackend(
        accessToken: 'token',
        refreshToken: 'refresh',
        tokoId: 'toko-1',
        outletId: 'outlet-1',
        penggunaId: 'pengguna-1',
        perangkatId: 'perangkat-1',
      );
}

class _FakeApi implements BackendApi {
  final List<Map<String, dynamic>> baris = [
    {'id': 'p1', 'tanggal': '2026-11-12', 'kategori': 'belanja_bahan', 'jumlah': 150000.0, 'catatan': 'Biji kopi'},
    {'id': 'p2', 'tanggal': '2026-11-12', 'kategori': 'gas_lpg', 'jumlah': 25000.0, 'catatan': null},
  ];
  final List<Map<String, dynamic>> dikirim = [];
  final List<String> dihapus = [];
  bool offline = false;
  final List<String> rentangDiminta = [];

  @override
  Future<Map<String, dynamic>> daftarPengeluaran({
    required String accessToken,
    required String dari,
    required String sampai,
  }) async {
    if (offline) throw const BackendException(message: 'Tidak ada koneksi');
    rentangDiminta.add('$dari..$sampai');
    final total = baris.fold<double>(0, (s, b) => s + (b['jumlah'] as double));
    return {
      'total': total,
      'per_kategori': [
        for (final b in baris) {'kategori': b['kategori'], 'total': b['jumlah']},
      ],
      'item': baris,
    };
  }

  @override
  Future<Map<String, dynamic>> catatPengeluaran({
    required String accessToken,
    required Map<String, dynamic> body,
  }) async {
    if (offline) throw const BackendException(message: 'Tidak ada koneksi');
    dikirim.add(body);
    baris.insert(0, {
      'id': body['id'],
      'tanggal': body['tanggal'],
      'kategori': body['kategori'],
      'jumlah': (body['jumlah'] as num).toDouble(),
      'catatan': body['catatan'],
    });
    return baris.first;
  }

  @override
  Future<void> hapusPengeluaran({required String accessToken, required String pengeluaranId}) async {
    dihapus.add(pengeluaranId);
    baris.removeWhere((b) => b['id'] == pengeluaranId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _buka(WidgetTester tester, _FakeApi api) async {
  await initializeDateFormatting('id_ID');
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      backendApiProvider.overrideWithValue(api),
      authSessionStoreProvider.overrideWithValue(_Sesi()),
    ],
    child: const MaterialApp(home: PengeluaranPage()),
  ));
  await tester.pumpAndSettle();
}

Future<void> _tutup(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 1));
}

void main() {
  test('rentang tanggal: hari ini, 7 hari, bulan ini', () {
    final sekarang = DateTime(2026, 11, 12, 15, 30);
    expect(tanggalApi(RentangPengeluaran.hariIni.tanggal(sekarang).$1), '2026-11-12');
    expect(tanggalApi(RentangPengeluaran.tujuhHari.tanggal(sekarang).$1), '2026-11-06');
    expect(tanggalApi(RentangPengeluaran.bulanIni.tanggal(sekarang).$1), '2026-11-01');
    expect(tanggalApi(RentangPengeluaran.bulanIni.tanggal(sekarang).$2), '2026-11-12');
  });

  testWidgets('menampilkan total, rincian kategori, dan daftar', (tester) async {
    await _buka(tester, _FakeApi());
    expect(find.text('Rp 175.000'), findsOneWidget);
    expect(find.text('Belanja bahan (HPP)'), findsWidgets);
    expect(find.text('Gas LPG'), findsWidgets);
    expect(find.byKey(const Key('pengeluaran.item.p1')), findsOneWidget);
    await _tutup(tester);
  });

  testWidgets('mengganti rentang memuat ulang dengan tanggal berbeda', (tester) async {
    final api = _FakeApi();
    await _buka(tester, api);
    await tester.tap(find.byKey(const Key('pengeluaran.rentang.bulanIni')));
    await tester.pumpAndSettle();
    expect(api.rentangDiminta.length, 2);
    expect(api.rentangDiminta.last.endsWith('..${tanggalApi(DateTime.now())}'), isTrue);
    expect(api.rentangDiminta.last.contains('-01..'), isTrue);
    await _tutup(tester);
  });

  testWidgets('mencatat pengeluaran mengirim id, kategori, jumlah dan memuat ulang daftar', (tester) async {
    final api = _FakeApi();
    await _buka(tester, api);
    await tester.tap(find.byKey(const Key('pengeluaran.tambah')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('pengeluaranForm.jumlah')), '40000');
    await tester.enterText(find.byKey(const Key('pengeluaranForm.catatan')), 'Cup dan sedotan');
    await tester.tap(find.byKey(const Key('pengeluaranForm.simpan')));
    await tester.pumpAndSettle();

    expect(api.dikirim.length, 1);
    final b = api.dikirim.single;
    expect(b['jumlah'], 40000);
    expect(b['kategori'], 'belanja_bahan');
    expect(b['outlet_id'], 'outlet-1');
    expect((b['id'] as String).length, 36);
    expect(find.text('Rp 215.000'), findsOneWidget);
    await _tutup(tester);
  });

  testWidgets('jumlah kosong ditolak di form tanpa memanggil server', (tester) async {
    final api = _FakeApi();
    await _buka(tester, api);
    await tester.tap(find.byKey(const Key('pengeluaran.tambah')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pengeluaranForm.simpan')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pengeluaranForm.error')), findsOneWidget);
    expect(api.dikirim, isEmpty);
    await _tutup(tester);
  });

  testWidgets('hapus meminta konfirmasi lalu menghapus', (tester) async {
    final api = _FakeApi();
    await _buka(tester, api);
    await tester.tap(find.byKey(const Key('pengeluaran.hapus.p2')));
    await tester.pumpAndSettle();
    expect(find.text('Hapus pengeluaran?'), findsOneWidget);
    await tester.tap(find.text('Hapus'));
    await tester.pumpAndSettle();
    expect(api.dihapus, ['p2']);
    expect(find.byKey(const Key('pengeluaran.item.p2')), findsNothing);
    await _tutup(tester);
  });

  testWidgets('offline: pesan butuh internet dan tombol coba lagi', (tester) async {
    final api = _FakeApi()..offline = true;
    await _buka(tester, api);
    expect(find.byKey(const Key('pengeluaran.error')), findsOneWidget);
    expect(find.textContaining('Butuh internet'), findsOneWidget);
    await _tutup(tester);
  });
}
