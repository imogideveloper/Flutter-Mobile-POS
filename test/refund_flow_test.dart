import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/core/network/auth_session_store.dart';
import 'package:apps_pos/core/network/backend_api.dart';
import 'package:apps_pos/core/network/backend_exception.dart';
import 'package:apps_pos/core/network/dio_backend_api.dart';
import 'package:apps_pos/core/providers/database_provider.dart';
import 'package:apps_pos/features/transaksi/data/local/tables/transaksi_table.dart';
import 'package:apps_pos/features/transaksi/domain/detail_transaksi.dart';
import 'package:apps_pos/features/transaksi/presentation/pages/refund_page.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// F3.D - RefundPage dites LANGSUNG (bukan lewat alur penuh dari
/// TransaksiDetailPage > PIN approval) - mintaOtorisasi()/pin_approval.dart
/// belum punya pola test tersendiri di codebase ini, jadi "sudah disetujui
/// PIN" diperlakukan sbg prasyarat yang sudah terpenuhi (tanggung jawab
/// TransaksiDetailPage yang TIDAK diubah oleh fitur ini), sama prinsip
/// dgn cara test lain fokus ke satu lapisan.
class _FakeAuthSessionStoreTerisi extends AuthSessionStore {
  _FakeAuthSessionStoreTerisi() : super(const FlutterSecureStorage());

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

class _FakeBackendApiRefund implements BackendApi {
  List<Map<String, dynamic>>? itemRefundableDikembalikan;
  Map<String, dynamic>? bodyRefundDiterima;

  @override
  Future<dynamic> getJson({
    required String accessToken,
    required String path,
    Map<String, dynamic>? query,
  }) => throw UnimplementedError();

  @override
  Future<dynamic> postJson({
    required String accessToken,
    required String path,
    Map<String, dynamic>? body,
  }) => throw UnimplementedError();

  @override
  Future<dynamic> patchJson({
    required String accessToken,
    required String path,
    required Map<String, dynamic> body,
  }) => throw UnimplementedError();

  @override
  Future<void> deleteJson({required String accessToken, required String path}) =>
      throw UnimplementedError();

  @override
  Future<List<Map<String, dynamic>>> ambilItemRefundable({
    required String accessToken,
    required String transaksiId,
  }) async =>
      itemRefundableDikembalikan ??
      [
        {
          'item_transaksi_id': 'item-1',
          'nama_produk': 'Kopi Hitam',
          'qty': '3',
          'harga_satuan': '15000',
          'qty_sudah_direfund': '0',
          'sisa_bisa_direfund': '3',
        },
      ];

  @override
  Future<Map<String, dynamic>> buatRefund({
    required String accessToken,
    required String transaksiId,
    required Map<String, dynamic> body,
  }) async {
    bodyRefundDiterima = body;
    return {
      'id': 'refund-1',
      'transaksi_id': transaksiId,
      'nomor': 'RFD-1',
      'alasan': body['alasan'],
      'total': '15000.00',
      'kas_dikembalikan': '15000.00',
      'kembalikan_stok': true,
      'items': [
        {'item_transaksi_id': 'item-1', 'qty': '1', 'jumlah': '15000.00'},
      ],
      'status_transaksi': 'refund_sebagian',
      'sisa_tagihan': '0.00',
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  testWidgets('pilih 1 item refund -> submit -> backend menerima body yang benar', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final fakeBackend = _FakeBackendApiRefund();

    final detail = DetailTransaksi(
      id: 'transaksi-1',
      nomorStruk: 'OUT1-0001',
      tanggal: DateTime.now().toUtc().millisecondsSinceEpoch,
      status: TransaksiStatus.selesai,
      items: const [],
      subtotal: 45000,
      rincianPajak: const [],
      totalPajak: 0,
      total: 45000,
      totalBayar: 45000,
      kembalian: 0,
    );

    // RefundPage DI-PUSH ke atas halaman lain (bukan jadi satu2nya route) -
    // sama seperti pemakaian sungguhan (lihat transaksi_detail_page.dart).
    // Navigator butuh >1 route supaya pop(true) di akhir _submit() benar2
    // valid, bukan pop route terakhir/satu2nya.
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWith((ref) => db),
        authSessionStoreProvider.overrideWithValue(_FakeAuthSessionStoreTerisi()),
        backendApiProvider.overrideWithValue(fakeBackend),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (context) => RefundPage(transaksi: detail, disetujuiOleh: 'owner-1'),
                  ),
                ),
                child: const Text('buka refund'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('buka refund'));
    await tester.pumpAndSettle();

    expect(find.text('Kopi Hitam'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.add_circle_outline));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('refundForm.alasan')), 'Rusak di jalan');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('refundForm.submit')));
    await tester.pumpAndSettle();

    expect(fakeBackend.bodyRefundDiterima, isNotNull);
    expect(fakeBackend.bodyRefundDiterima!['alasan'], 'Rusak di jalan');
    expect(fakeBackend.bodyRefundDiterima!['kembalikan_stok'], true);
    final items = fakeBackend.bodyRefundDiterima!['items'] as List;
    expect(items, hasLength(1));
    expect(items.single['item_transaksi_id'], 'item-1');
    expect(items.single['qty'], '1');

    expect(find.text('Refund berhasil - Rp15.000'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('temuan#4 - offline saat muat item refundable menampilkan pesan netral, bukan error teknis',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final fakeBackend = _FakeBackendApiOffline();

    final detail = DetailTransaksi(
      id: 'transaksi-1',
      nomorStruk: 'OUT1-0001',
      tanggal: DateTime.now().toUtc().millisecondsSinceEpoch,
      status: TransaksiStatus.selesai,
      items: const [],
      subtotal: 45000,
      rincianPajak: const [],
      totalPajak: 0,
      total: 45000,
      totalBayar: 45000,
      kembalian: 0,
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWith((ref) => db),
        authSessionStoreProvider.overrideWithValue(_FakeAuthSessionStoreTerisi()),
        backendApiProvider.overrideWithValue(fakeBackend),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (context) => RefundPage(transaksi: detail, disetujuiOleh: 'owner-1'),
                  ),
                ),
                child: const Text('buka refund'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('buka refund'));
    await tester.pumpAndSettle();

    expect(find.text('Refund butuh koneksi internet'), findsOneWidget);
    expect(find.textContaining('Gagal memuat item'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}

class _FakeBackendApiOffline implements BackendApi {
  @override
  Future<dynamic> getJson({
    required String accessToken,
    required String path,
    Map<String, dynamic>? query,
  }) => throw UnimplementedError();

  @override
  Future<dynamic> postJson({
    required String accessToken,
    required String path,
    Map<String, dynamic>? body,
  }) => throw UnimplementedError();

  @override
  Future<dynamic> patchJson({
    required String accessToken,
    required String path,
    required Map<String, dynamic> body,
  }) => throw UnimplementedError();

  @override
  Future<void> deleteJson({required String accessToken, required String path}) =>
      throw UnimplementedError();

  @override
  Future<List<Map<String, dynamic>>> ambilItemRefundable({
    required String accessToken,
    required String transaksiId,
  }) async =>
      throw const BackendException(message: 'Tidak bisa menghubungi server - periksa koneksi internet');

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
