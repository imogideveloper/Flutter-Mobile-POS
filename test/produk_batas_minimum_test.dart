import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/core/network/auth_session_store.dart';
import 'package:apps_pos/core/network/backend_api.dart';
import 'package:apps_pos/core/network/connectivity_provider.dart';
import 'package:apps_pos/core/network/dio_backend_api.dart';
import 'package:apps_pos/core/providers/database_provider.dart';
import 'package:apps_pos/core/providers/session_provider.dart';
import 'package:apps_pos/core/providers/toko_profile_provider.dart';
import 'package:apps_pos/features/produk/data/local/tables/produk_table.dart' hide Produk;
import 'package:apps_pos/features/produk/domain/produk.dart';
import 'package:apps_pos/features/produk/presentation/pages/produk_form_page.dart';
import 'package:apps_pos/main.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

Widget _bungkusRouter(Widget child) => MaterialApp.router(
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

class _LangsungLogin extends PenggunaSessionNotifier {
  @override
  String? build() => 'pengguna-default';
}

class _FakeAuthSessionStoreTerisi extends AuthSessionStore {
  _FakeAuthSessionStoreTerisi() : super(const FlutterSecureStorage());

  @override
  Future<SesiBackend?> muat() async => const SesiBackend(
        accessToken: 'token',
        refreshToken: 'refresh',
        tokoId: 'toko-default',
        outletId: 'outlet-default',
        penggunaId: 'pengguna-default',
        perangkatId: 'perangkat-1',
      );
}

/// Tahap 5b lanjutan - produk sekarang ONLINE-DIRECT (lihat catatan di
/// produk_form_page.dart) - tambah & edit sama2 lewat POST/PATCH /produk.
class _FakeBackendApiProduk implements BackendApi {
  _FakeBackendApiProduk({this.idDikembalikan = 'produk-baru'});

  final String idDikembalikan;

  @override
  Future<dynamic> postJson({
    required String accessToken,
    required String path,
    Map<String, dynamic>? body,
  }) async => _responFromBody(idDikembalikan, body!);

  @override
  Future<dynamic> patchJson({
    required String accessToken,
    required String path,
    required Map<String, dynamic> body,
  }) async {
    // path = '/produk/<id>' - ambil id dari path spy respons konsisten
    // dgn produk yang sedang diedit.
    final id = path.split('/').last;
    return _responFromBody(id, body);
  }

  Map<String, dynamic> _responFromBody(String id, Map<String, dynamic> body) => {
        'id': id,
        'toko_id': 'toko-default',
        'kategori_id': null,
        'satuan_id': null,
        'sku': body['sku'],
        'barcode': body['barcode'],
        'nama': body['nama'],
        'tipe': body['tipe'],
        'lacak_stok': body['lacak_stok'],
        'hpp': body['hpp'],
        'harga_jual': body['harga_jual'],
        'aktif': body['aktif'],
      };

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

// Tanpa anotasi tipe return eksplisit (Override tidak diekspor publik dari
// flutter_riverpod) - sama pola dgn overridesSudahLogin di test_helpers.dart.
_overridesOnline(AppDatabase db, {String idDikembalikan = 'produk-baru'}) => [
      appDatabaseProvider.overrideWith((ref) => db),
      currentPenggunaIdProvider.overrideWith(_LangsungLogin.new),
      authSessionStoreProvider.overrideWithValue(_FakeAuthSessionStoreTerisi()),
      backendApiProvider.overrideWithValue(_FakeBackendApiProduk(idDikembalikan: idDikembalikan)),
      tokoProfileProvider.overrideWith((ref) async => null),
      isOnlineProvider.overrideWith((ref) => Stream.value(true)),
    ];

/// Regresi utk bug nyata yang dilaporkan pengguna: field "Ingatkan jika
/// sisa" di form Tambah Produk terlihat normal di layar, tapi nilainya
/// TIDAK PERNAH tersimpan (produk_form_page.dart._simpan() dulu tidak
/// membaca _batasMinController sama sekali) - akibatnya produk manapun
/// tidak pernah muncul di tab "Stok menipis" walau sudah diisi batas
/// minimumnya. Lihat perbaikan di produk_form_page.dart + stok_dao.dart
/// (StokDao.catatMutasi sekarang menerima parameter batasMinimum).
///
/// Sejak produk jadi online-direct (lihat produk_form_page.dart), test
/// ini juga sekaligus jadi bukti alur baru itu tidak merusak perbaikan
/// batas minimum yang sudah ada - stok awal/batas minimum tetap murni
/// lokal, cuma data produk intinya yang sekarang lewat server dulu.
void main() {
  testWidgets(
      'tambah produk dgn stok awal <= batas minimum langsung muncul di tab Stok menipis',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(ProviderScope(
      overrides: _overridesOnline(db, idDikembalikan: 'p-kabel'),
      child: const AppsPosApp(),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Produk'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('produkForm.nama')), 'Kabel');
    await tester.enterText(find.byKey(const Key('produkForm.hargaJual')), '15000');
    await tester.enterText(find.byKey(const Key('produkForm.stokAwal')), '5');
    await tester.enterText(find.byKey(const Key('produkForm.batasMinimum')), '10');

    for (var i = 0; i < 5; i++) {
      await tester.drag(find.byKey(const Key('produkForm.scrollView')), const Offset(0, -300));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simpan produk'));
    await tester.pumpAndSettle();

    // Baris stok benar2 tersimpan dgn batasMinimum yang diisi di form -
    // bukan cuma terlihat tersimpan di UI.
    final stokRows = await db.select(db.stok).get();
    expect(stokRows, hasLength(1));
    expect(stokRows.single.jumlah, 5);
    expect(stokRows.single.batasMinimum, 10);

    await tester.tap(find.textContaining('Stok menipis'));
    await tester.pumpAndSettle();

    expect(find.text('Kabel'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets(
      'edit produk lama yang belum ada batas minimum - sekarang bisa diisi lewat Edit',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    // Simulasikan persis laporan pengguna: produk "Kabel" sudah ada,
    // sudah ada baris stok, tapi batasMinimum-nya 0 (belum pernah
    // tersimpan - konsekuensi dari bug yang diperbaiki di atas).
    await db.produkDao.upsertProduk(ProdukCompanion.insert(
      id: 'p-kabel',
      tokoId: 'toko-default',
      nama: 'Kabel',
      tipe: ProdukTipe.barang,
      lacakStok: const Value(true),
      hargaJual: const Value(15000),
      createdAt: 0,
      updatedAt: 0,
    ));
    await db.into(db.stok).insert(StokCompanion.insert(
          id: 's-kabel',
          outletId: 'outlet-default',
          produkId: 'p-kabel',
          jumlah: const Value(5),
          createdAt: 0,
          updatedAt: 0,
        ));

    const produk = Produk(
      id: 'p-kabel',
      tokoId: 'toko-default',
      nama: 'Kabel',
      tipe: ProdukTipe.barang,
      lacakStok: true,
      punyaVarian: false,
      pakaiResep: false,
      hpp: 0,
      hargaJual: 15000,
      dijual: true,
      aktif: true,
    );

    await tester.pumpWidget(ProviderScope(
      overrides: _overridesOnline(db, idDikembalikan: 'p-kabel'),
      child: _bungkusRouter(const ProdukFormPage(produk: produk)),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('produkForm.stokAwal')), findsNothing);
    expect(find.byKey(const Key('produkForm.batasMinimum')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('produkForm.batasMinimum')), '10');
    for (var i = 0; i < 5; i++) {
      await tester.drag(find.byKey(const Key('produkForm.scrollView')), const Offset(0, -300));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simpan produk'));
    await tester.pumpAndSettle();

    final stokRow = await (db.select(db.stok)..where((t) => t.produkId.equals('p-kabel'))).getSingle();
    expect(stokRow.batasMinimum, 10);
    expect(stokRow.jumlah, 5, reason: 'edit batas minimum tidak boleh mengubah saldo stok');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
