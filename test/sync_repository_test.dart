import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/core/harga/kalkulator.dart' as k;
import 'package:apps_pos/features/transaksi/data/transaksi_repository.dart';
import 'package:apps_pos/features/transaksi/domain/item_keranjang.dart';
import 'package:apps_pos/features/shift/data/local/tables/kas_shift_table.dart' show KasShiftJenis;
import 'package:apps_pos/features/shift/data/local/tables/shift_table.dart' show ShiftStatus;
import 'package:apps_pos/core/network/auth_session_store.dart';
import 'package:apps_pos/core/network/backend_api.dart';
import 'package:apps_pos/core/network/sync_repository.dart';
import 'package:apps_pos/features/produk/data/local/tables/produk_table.dart';
import 'package:apps_pos/features/transaksi/data/local/tables/metode_bayar_table.dart';
import 'package:apps_pos/features/transaksi/data/local/tables/pembayaran_table.dart';
import 'package:apps_pos/features/transaksi/data/local/tables/transaksi_table.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tanpa network/device sungguhan di sandbox ini - FakeBackendApi meniru
/// kontrak /sync/push dan /sync/pull persis spt backend/app/services/
/// sync_service.py (lihat juga dio_backend_api.dart utk pemetaan field).
class _FakeBackendApi implements BackendApi {
  // Pengeluaran tidak ikut sync (langsung ke server); tidak dipakai di tes ini.
  @override
  Future<Map<String, dynamic>> laporanRekapPajak({required String accessToken, required String dari, required String sampai}) =>
      throw UnimplementedError();
  @override
  Future<Map<String, dynamic>> laporanPphFinal({required String accessToken, required String dari, required String sampai}) =>
      throw UnimplementedError();
  @override
  Future<Map<String, dynamic>> imporProduk({required String accessToken, required List<Map<String, dynamic>> baris, required bool simulasi}) =>
      throw UnimplementedError();
  @override
  Future<Map<String, dynamic>> absensiSaya({required String accessToken}) => throw UnimplementedError();
  @override
  Future<Map<String, dynamic>> absenMasuk({required String accessToken, String? outletId, String? catatan}) =>
      throw UnimplementedError();
  @override
  Future<Map<String, dynamic>> absenKeluar({required String accessToken, String? catatan}) => throw UnimplementedError();
  @override
  Future<Map<String, dynamic>> daftarAbsensi({required String accessToken, required String dari, required String sampai, required int tzMenit}) =>
      throw UnimplementedError();
  @override
  Future<Map<String, dynamic>> imporPelanggan({required String accessToken, required List<Map<String, dynamic>> baris, required bool simulasi}) =>
      throw UnimplementedError();
  @override
  Future<Map<String, dynamic>> laporanLabaRugi({required String accessToken, required String dari, required String sampai}) =>
      throw UnimplementedError();
  @override
  Future<Map<String, dynamic>> daftarPengeluaran({required String accessToken, required String dari, required String sampai}) =>
      throw UnimplementedError();
  @override
  Future<Map<String, dynamic>> catatPengeluaran({required String accessToken, required Map<String, dynamic> body}) =>
      throw UnimplementedError();
  @override
  Future<void> hapusPengeluaran({required String accessToken, required String pengeluaranId}) =>
      throw UnimplementedError();

  List<Map<String, dynamic>> transaksiDiterima = [];
  List<Map<String, dynamic>> pembayaranDiterima = [];
  List<Map<String, dynamic>> pesananBatalDiterima = [];
  List<Map<String, dynamic>> statusPesananDiterima = [];
  List<Map<String, dynamic>> shiftDiterima = [];
  List<Map<String, dynamic>> kasShiftDiterima = [];
  /// Id transaksi yang dijawab 'ditolak' oleh server palsu ini.
  Set<String> idDitolak = {};
  SyncPullResult? pullResponse;

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
  Future<void> putJsonIds({
    required String accessToken,
    required String path,
    required List<String> ids,
  }) => throw UnimplementedError();

  @override
  Future<dynamic> putJsonBody({
    required String accessToken,
    required String path,
    required Map<String, dynamic> body,
  }) => throw UnimplementedError();

  @override
  Future<PinLoginResult> pinLoginOnline({
    required String perangkatId,
    required String penggunaId,
    required String pin,
  }) => throw UnimplementedError();

  @override
  Future<OtpRequestResult> otpRequest({required String noHp}) =>
      throw UnimplementedError();

  @override
  Future<AuthResult> otpVerify({
    required String noHp,
    required String kode,
    required String deviceUid,
    required String namaPerangkat,
    String? platform,
    String? namaToko,
    String? jenisUsaha,
    String? namaPemilik,
    String? pin,
  }) => throw UnimplementedError();

  @override
  Future<String> refreshAccessToken({required String refreshToken}) =>
      throw UnimplementedError();

  @override
  Future<SyncPushResult> syncPush({
    required String accessToken,
    required String perangkatId,
    required List<Map<String, dynamic>> transaksi,
    List<Map<String, dynamic>> shift = const [],
    // Kas masuk/keluar di dalam shift; dikirim bersama shiftnya (server idempoten per id).
    List<Map<String, dynamic>> kasShift = const [],
    List<Map<String, dynamic>> pembayaran = const [],
    List<Map<String, dynamic>> pesananBatal = const [],
    List<Map<String, dynamic>> statusPesanan = const [],
  }) async {
    transaksiDiterima = transaksi;
    shiftDiterima = shift;
    kasShiftDiterima = kasShift;
    pembayaranDiterima = pembayaran;
    pesananBatalDiterima = pesananBatal;
    statusPesananDiterima = statusPesanan;
    return SyncPushResult(
      transaksi: transaksi
          .map((t) => HasilPushItem(
                id: t['id'] as String,
                status: idDitolak.contains(t['id']) ? 'ditolak' : 'diterima',
                pesan: idDitolak.contains(t['id']) ? 'Shift tidak ditemukan' : null,
              ))
          .toList(),
      pembayaran: pembayaran
          .map((p) => HasilPushItem(id: p['id'] as String, status: 'diterima'))
          .toList(),
      pesananBatal: pesananBatal
          .map((p) => HasilPushItem(id: p['id'] as String, status: 'diterima'))
          .toList(),
      statusPesanan: statusPesanan
          .map((p) => HasilPushItem(id: p['id'] as String, status: 'diterima'))
          .toList(),
    );
  }

  @override
  Future<SyncPullResult> syncPull({
    required String accessToken,
    required String perangkatId,
    required String since,
    String? outletId,
    int limit = 500,
  }) async {
    final hasil = pullResponse!;
    pullResponse = const SyncPullResult(
      waktuPull: '2026-01-01T00:00:00Z',
      produk: [],
      kategori: [],
      satuan: [],
      pajak: [],
      promo: [],
      metodeBayar: [],
      stok: [],
      hargaOutlet: [],
      hargaGrosir: [],
      tipeOrderPajak: [],
      pengaturanOutlet: [],
      hasMore: {},
      paket: null,
      kodeFitur: [],
      batasFitur: {},
    );
    return hasil;
  }

  @override
  Future<Map<String, dynamic>> ambilPengaturanOutlet({
    required String accessToken,
    required String outletId,
  }) =>
      throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> ubahPengaturanOutlet({
    required String accessToken,
    required String outletId,
    required Map<String, dynamic> body,
  }) =>
      throw UnimplementedError();

  @override
  Future<String> uploadLogoToko({
    required String accessToken,
    required List<int> bytes,
    required String namaFile,
  }) =>
      throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> ubahMetodeBayar({
    required String accessToken,
    required String metodeBayarId,
    required Map<String, dynamic> body,
  }) =>
      throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> ambilTransaksi({
    required String accessToken,
    required String outletId,
    required String dariTanggal,
    required String sampaiTanggal,
    int limit = 200,
    int offset = 0,
  }) =>
      throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> ambilDetailTransaksi({
    required String accessToken,
    required String transaksiId,
  }) =>
      throw UnimplementedError();

  @override
  Future<List<Map<String, dynamic>>> ambilItemRefundable({
    required String accessToken,
    required String transaksiId,
  }) =>
      throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> buatRefund({
    required String accessToken,
    required String transaksiId,
    required Map<String, dynamic> body,
  }) =>
      throw UnimplementedError();

  @override
  Future<List<Map<String, dynamic>>> ambilDaftarPaket({required String accessToken}) =>
      throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> ambilLanggananSaya({required String accessToken}) =>
      throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> ajukanUpgrade({
    required String accessToken,
    required Map<String, dynamic> body,
  }) =>
      throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> checkoutUpgrade({
    required String accessToken,
    required Map<String, dynamic> body,
  }) =>
      throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> statusCheckoutUpgrade({
    required String accessToken,
    required String permintaanId,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> batalkanPesananTersimpan({
    required String accessToken,
    required String pesananId,
    required Map<String, dynamic> body,
  }) =>
      throw UnimplementedError();
}

class _FakeAuthSessionStore extends AuthSessionStore {
  _FakeAuthSessionStore() : super(const FlutterSecureStorage());

  SesiBackend? sesi = const SesiBackend(
    accessToken: 'token',
    refreshToken: 'refresh',
    tokoId: 'toko-asli',
    outletId: 'outlet-asli',
    penggunaId: 'pengguna-asli',
    perangkatId: 'perangkat-asli',
  );
  String lastSyncAt = DateTime.utc(1970).toIso8601String();

  @override
  Future<SesiBackend?> muat() async => sesi;

  @override
  Future<String> ambilLastSyncAt() async => lastSyncAt;

  @override
  Future<void> simpanLastSyncAt(String iso8601) async => lastSyncAt = iso8601;
}

void main() {
  late AppDatabase db;
  late _FakeBackendApi api;
  late _FakeAuthSessionStore sessionStore;
  late SyncRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    api = _FakeBackendApi();
    sessionStore = _FakeAuthSessionStore();
    repo = SyncRepository(
      api: api,
      sessionStore: sessionStore,
      transaksiDao: db.transaksiDao,
      produkDao: db.produkDao,
      satuanDao: db.satuanDao,
      pajakDao: db.pajakDao,
      promoDao: db.promoDao,
      metodeBayarDao: db.metodeBayarDao,
      stokDao: db.stokDao,
      fiturDao: db.fiturDao,
      hargaDao: db.hargaDao,
      tipeOrderDao: db.tipeOrderDao,
      penggunaDao: db.penggunaDao,
      pelangganDao: db.pelangganDao,
    );
  });

  tearDown(() => db.close());

  test('push: transaksi belum sync dikirim lalu ditandai sudah sync', () async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await db
        .into(db.metodeBayar)
        .insert(
          MetodeBayarCompanion.insert(
            id: 'metode-1',
            tokoId: 'toko-asli',
            nama: 'Tunai',
            tipe: MetodeBayarTipe.tunai,
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db
        .into(db.transaksi)
        .insert(
          TransaksiCompanion.insert(
            id: 'trx-1',
            tokoId: 'toko-asli',
            outletId: 'outlet-asli',
            penggunaId: 'pengguna-asli',
            nomorStruk: 'OUT1-001',
            tanggal: now,
            status: TransaksiStatus.selesai,
            subtotal: const Value(15000),
            totalDiskon: const Value(0),
            totalPajak: const Value(1650),
            pembulatan: const Value(0),
            total: const Value(16650),
            totalBayar: const Value(16650),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db
        .into(db.pembayaran)
        .insert(
          PembayaranCompanion.insert(
            id: 'bayar-1',
            transaksiId: 'trx-1',
            metodeBayarId: 'metode-1',
            jumlah: 15000,
            status: PembayaranStatus.berhasil,
            createdAt: now,
            updatedAt: now,
          ),
        );

    api.pullResponse = const SyncPullResult(
      waktuPull: '2026-01-01T00:00:00Z',
      produk: [],
      kategori: [],
      satuan: [],
      pajak: [],
      promo: [],
      metodeBayar: [],
      stok: [],
      hargaOutlet: [],
      hargaGrosir: [],
      tipeOrderPajak: [],
      pengaturanOutlet: [],
      hasMore: {},
      paket: null,
      kodeFitur: [],
      batasFitur: {},
    );

    final hasil = await repo.jalankan();

    expect(hasil.transaksiTerkirim, 1);
    expect(hasil.transaksiDitolak, 0);
    expect(api.transaksiDiterima.single['nomor_struk'], 'OUT1-001');
    expect(api.transaksiDiterima.single['metode_bayar_id'], 'metode-1');
    // Tahap 3a Part B/C.2 - breakdown yg sudah dihitung HP sendiri (kolom
    // lokal transaksi) WAJIB ikut terkirim, server menyimpannya apa
    // adanya utk push offline.
    expect(api.transaksiDiterima.single['subtotal_klien'], '15000');
    expect(api.transaksiDiterima.single['total_pajak_klien'], '1650');
    expect(api.transaksiDiterima.single['total_klien'], '16650');

    final sisaBelumSync = await db.transaksiDao.transaksiBelumSync();
    expect(sisaBelumSync, isEmpty);
  });

  test(
    'temuan A.1 (tahap 5) - penanda QRIS manual ikut terkirim utuh lewat split_pembayaran (dulu dibuang)',
    () async {
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      await db.into(db.metodeBayar).insert(
            MetodeBayarCompanion.insert(
              id: 'metode-qris',
              tokoId: 'toko-asli',
              nama: 'QRIS',
              tipe: MetodeBayarTipe.qris,
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.into(db.transaksi).insert(
            TransaksiCompanion.insert(
              id: 'trx-qris',
              tokoId: 'toko-asli',
              outletId: 'outlet-asli',
              penggunaId: 'pengguna-asli',
              nomorStruk: 'OUT1-QRIS-1',
              tanggal: now,
              status: TransaksiStatus.selesai,
              total: const Value(15000),
              totalBayar: const Value(15000),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.into(db.pembayaran).insert(
            PembayaranCompanion.insert(
              id: 'bayar-qris',
              transaksiId: 'trx-qris',
              metodeBayarId: 'metode-qris',
              jumlah: 15000,
              status: PembayaranStatus.berhasil,
              payloadGateway: const Value('{"metode":"qris_statis_manual","dikonfirmasi_kasir":true}'),
              createdAt: now,
              updatedAt: now,
            ),
          );

      api.pullResponse = const SyncPullResult(
        waktuPull: '2026-01-01T00:00:00Z',
        produk: [],
        kategori: [],
        satuan: [],
        pajak: [],
        promo: [],
        metodeBayar: [],
        stok: [],
        hargaOutlet: [],
        hargaGrosir: [],
        tipeOrderPajak: [],
        pengaturanOutlet: [],
        hasMore: {},
        paket: null,
        kodeFitur: [],
        batasFitur: {},
      );

      await repo.jalankan();

      final splitPembayaran = api.transaksiDiterima.single['split_pembayaran'] as List;
      expect(splitPembayaran, hasLength(1));
      expect(splitPembayaran.single['payload_gateway'], {
        'metode': 'qris_statis_manual',
        'dikonfirmasi_kasir': true,
      });
    },
  );

  test(
    'temuan#1 - push transaksi dgn diskon member+promo sekaligus tidak crash, promo_id & rincian terkirim benar',
    () async {
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      await db
          .into(db.metodeBayar)
          .insert(
            MetodeBayarCompanion.insert(
              id: 'metode-1',
              tokoId: 'toko-asli',
              nama: 'Tunai',
              tipe: MetodeBayarTipe.tunai,
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db
          .into(db.transaksi)
          .insert(
            TransaksiCompanion.insert(
              id: 'trx-2',
              tokoId: 'toko-asli',
              outletId: 'outlet-asli',
              penggunaId: 'pengguna-asli',
              nomorStruk: 'OUT1-002',
              tanggal: now,
              status: TransaksiStatus.selesai,
              subtotal: const Value(100000),
              totalDiskon: const Value(20000),
              totalPajak: const Value(8800),
              pembulatan: const Value(0),
              total: const Value(88800),
              totalBayar: const Value(88800),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db
          .into(db.pembayaran)
          .insert(
            PembayaranCompanion.insert(
              id: 'bayar-2',
              transaksiId: 'trx-2',
              metodeBayarId: 'metode-1',
              jumlah: 88800,
              status: PembayaranStatus.berhasil,
              createdAt: now,
              updatedAt: now,
            ),
          );
      // 2 baris TransaksiPromo sekaligus - dulu bikin sync CRASH (StateError
      // dari getSingleOrNull di promoUntukTransaksi, lihat transaksi_dao.dart).
      await db.into(db.transaksiPromo).insert(
            TransaksiPromoCompanion.insert(
              id: 'tp-member',
              transaksiId: 'trx-2',
              nama: 'Diskon member',
              jumlahDiskon: 10000,
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.into(db.transaksiPromo).insert(
            TransaksiPromoCompanion.insert(
              id: 'tp-promo',
              transaksiId: 'trx-2',
              promoId: const Value('promo-asli-1'),
              nama: 'Promo Lebaran',
              jumlahDiskon: 10000,
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.into(db.transaksiPajak).insert(
            TransaksiPajakCompanion.insert(
              id: 'tj-ppn',
              transaksiId: 'trx-2',
              pajakId: const Value('pajak-ppn-1'),
              nama: 'PPN',
              persen: 11,
              jumlah: 8800,
              createdAt: now,
              updatedAt: now,
            ),
          );

      api.pullResponse = const SyncPullResult(
        waktuPull: '2026-01-01T00:00:00Z',
        produk: [],
        kategori: [],
        satuan: [],
        pajak: [],
        promo: [],
        metodeBayar: [],
        stok: [],
        hargaOutlet: [],
        hargaGrosir: [],
        tipeOrderPajak: [],
        pengaturanOutlet: [],
        hasMore: {},
        paket: null,
        kodeFitur: [],
        batasFitur: {},
      );

      final hasil = await repo.jalankan();

      expect(hasil.transaksiTerkirim, 1);
      expect(api.transaksiDiterima.single['promo_id'], 'promo-asli-1');

      final rincianPajak = api.transaksiDiterima.single['rincian_pajak_klien'] as List;
      expect(rincianPajak, hasLength(1));
      expect(rincianPajak.single['pajak_id'], 'pajak-ppn-1');
      expect(rincianPajak.single['jumlah'], '8800');

      final rincianPromo = api.transaksiDiterima.single['rincian_promo_klien'] as List;
      expect(rincianPromo, hasLength(2));
      final namaRincian = rincianPromo.map((p) => p['nama']).toSet();
      expect(namaRincian, {'Diskon member', 'Promo Lebaran'});
    },
  );

  test(
    'temuan#2 - pembatalan pesanan tersimpan yang belum sync ikut dipush walau tidak ada transaksi baru',
    () async {
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      await db.into(db.pesananBatal).insert(
            PesananBatalCompanion.insert(
              id: 'draft-1',
              alasan: 'Dibatalkan offline',
              disetujuiOleh: const Value('owner-1'),
              isiPesanan: '[]',
              total: 15000,
              nomorStruk: 'DRAFT1',
              dibatalkanPada: now,
              createdAt: now,
              updatedAt: now,
            ),
          );

      api.pullResponse = const SyncPullResult(
        waktuPull: '2026-01-01T00:00:00Z',
        produk: [],
        kategori: [],
        satuan: [],
        pajak: [],
        promo: [],
        metodeBayar: [],
        stok: [],
        hargaOutlet: [],
        hargaGrosir: [],
        tipeOrderPajak: [],
        pengaturanOutlet: [],
        hasMore: {},
        paket: null,
        kodeFitur: [],
        batasFitur: {},
      );

      await repo.jalankan();

      expect(api.pesananBatalDiterima, hasLength(1));
      expect(api.pesananBatalDiterima.single['id'], 'draft-1');
      expect(api.pesananBatalDiterima.single['alasan'], 'Dibatalkan offline');
      expect(api.pesananBatalDiterima.single['disetujui_oleh'], 'owner-1');

      final sisa = await db.transaksiDao.pembatalanPesananBelumSync();
      expect(sisa, isEmpty, reason: 'harus ditandai sudah sync setelah diterima server');
    },
  );

  test('push: transaksi dari checkout nyata membawa HPP produk (snapshot) ke payload sync', () async {
    await db.produkDao.upsertProduk(ProdukCompanion.insert(
      id: 'kopi',
      tokoId: 'toko-asli',
      nama: 'Kopi Susu',
      tipe: ProdukTipe.barang,
      hargaJual: const Value(18000),
      hpp: const Value(7000),
      createdAt: 0,
      updatedAt: 0,
    ));
    final items = [const ItemKeranjang(produkId: 'kopi', namaProduk: 'Kopi Susu', hargaSatuan: 18000, qty: 3, lacakStok: false)];
    await TransaksiRepository(db.transaksiDao, db.stokDao, db.produkDao).checkout(
      tokoId: 'toko-asli',
      outletId: 'outlet-asli',
      shiftId: 'shift-uji',
      penggunaId: 'pengguna-asli',
      metodeBayarId: 'metode-tunai-default',
      items: items,
      hasil: k.hitung(k.TransaksiInput(items: [
        k.ItemInput(produkId: 'kopi', varianId: null, namaProduk: 'Kopi Susu', qty: 3, hargaJual: 18000),
      ])),
      totalBayar: 54000,
    );
    api.pullResponse = const SyncPullResult(
      waktuPull: '2026-01-01T00:00:00Z',
      produk: [],
      kategori: [],
      satuan: [],
      pajak: [],
      promo: [],
      metodeBayar: [],
      stok: [],
      hargaOutlet: [],
      hargaGrosir: [],
      tipeOrderPajak: [],
      pengaturanOutlet: [],
      hasMore: {},
      paket: null,
      kodeFitur: [],
      batasFitur: {},
    );

    await repo.jalankan();

    final item = (api.transaksiDiterima.single['items'] as List).single as Map<String, dynamic>;
    expect(item['hpp_satuan'], '7000', reason: 'HPP produk saat checkout harus ikut terkirim, bukan 0');
    expect(item['harga_satuan'], '18000');
    expect(api.transaksiDiterima.single['subtotal_klien'], '54000');
  });

  test(
    'pull: produk/pajak/promo/stok diupsert dgn konversi tipe yg benar',
    () async {
      api.pullResponse = const SyncPullResult(
        waktuPull: '2026-01-01T00:00:00Z',
        produk: [
          {
            'id': 'produk-1',
            'kategori_id': null,
            'satuan_id': null,
            'sku': null,
            'barcode': null,
            'nama': 'Tepung',
            'tipe': 'bahan_baku',
            'lacak_stok': true,
            'hpp': '8000.00',
            'harga_jual': '12000.00',
            'aktif': true,
            'updated_at': '2026-01-01T00:00:00Z',
            'deleted_at': null,
          },
        ],
        kategori: [],
        satuan: [],
        pajak: [
          {
            'id': 'pajak-1',
            'nama': 'PPN',
            'tipe': 'pajak',
            'persen': '11.00',
            'termasuk_harga': false,
            'urutan': 0,
            'aktif': true,
            'updated_at': '2026-01-01T00:00:00Z',
            'deleted_at': null,
          },
        ],
        promo: [],
        metodeBayar: [],
        stok: [
          {
            'id': 'stok-1',
            'outlet_id': 'outlet-asli',
            'produk_id': 'produk-1',
            'varian_id': null,
            'jumlah': '25.5',
            'batas_minimum': '5.0',
            'hpp_rata_rata': '8000.00',
            'updated_at': '2026-01-01T00:00:00Z',
            'deleted_at': null,
          },
        ],
        hargaOutlet: [],
        hargaGrosir: [],
        tipeOrderPajak: [],
        pengaturanOutlet: [],
        hasMore: {},
        paket: null,
        kodeFitur: [],
        batasFitur: {},
      );

      final hasil = await repo.jalankan();
      expect(hasil.jumlahDiterimaPull, 3);

      final produk = await db.produkDao.produkById('produk-1');
      expect(produk, isNotNull);
      expect(produk!.tipe, ProdukTipe.bahanBaku);
      expect(produk.hpp, 8000);
      expect(produk.hargaJual, 12000);

      final pajakRows = await db.select(db.pajak).get();
      expect(pajakRows.single.persen, 11.0);

      final stokRows = await db.select(db.stok).get();
      expect(stokRows.single.jumlah, 25.5);
      expect(stokRows.single.batasMinimum, 5.0);
      expect(stokRows.single.hppRataRata, 8000);

      expect(sessionStore.lastSyncAt, '2026-01-01T00:00:00.000Z');
    },
  );

  test(
    'pull: promo khusus ulang tahun dan tanggal lahir pelanggan (yyyymmdd) tersimpan di HP',
    () async {
      api.pullResponse = const SyncPullResult(
        waktuPull: '2026-01-01T00:00:00Z',
        produk: [],
        kategori: [],
        satuan: [],
        pajak: [],
        promo: [
          {
            'id': 'promo-bday',
            'nama': 'Diskon Ulang Tahun',
            'kode': null,
            'tipe': 'persen',
            'nilai': '20.00',
            'min_belanja': '0.00',
            'maks_diskon': null,
            'aktif': true,
            'khusus_ulang_tahun': true,
            'updated_at': '2026-01-01T00:00:00Z',
            'deleted_at': null,
          },
          {
            'id': 'promo-biasa',
            'nama': 'Promo Jumat',
            'kode': null,
            'tipe': 'nominal',
            'nilai': '5000.00',
            'min_belanja': '0.00',
            'maks_diskon': null,
            'aktif': true,
            'updated_at': '2026-01-01T00:00:00Z',
            'deleted_at': null,
          },
        ],
        metodeBayar: [],
        pelanggan: [
          {
            'id': 'pel-1',
            'nama': 'Sari',
            'no_hp': '081200000001',
            'email': null,
            'tanggal_lahir': '1995-04-12',
            'poin': 0,
            'total_belanja': '0.00',
            'updated_at': '2026-01-01T00:00:00Z',
            'deleted_at': null,
          },
          {
            'id': 'pel-2',
            'nama': 'Tanpa Lahir',
            'no_hp': null,
            'email': null,
            'tanggal_lahir': null,
            'poin': 0,
            'total_belanja': '0.00',
            'updated_at': '2026-01-01T00:00:00Z',
            'deleted_at': null,
          },
        ],
        stok: [],
        hargaOutlet: [],
        hargaGrosir: [],
        tipeOrderPajak: [],
        pengaturanOutlet: [],
        hasMore: {},
        paket: null,
        kodeFitur: [],
        batasFitur: {},
      );

      await repo.jalankan();

      final promo = {for (final p in await db.select(db.promo).get()) p.id: p};
      expect(promo['promo-bday']!.khususUlangTahun, isTrue);
      expect(promo['promo-biasa']!.khususUlangTahun, isFalse, reason: 'server lama tanpa field = bukan ulang tahun');

      final pelanggan = {for (final p in await db.select(db.pelanggan).get()) p.id: p};
      expect(pelanggan['pel-1']!.tanggalLahir, 19950412);
      expect(pelanggan['pel-2']!.tanggalLahir, isNull);
    },
  );

  test(
    'pull: harga_outlet/harga_grosir/tipe_order_pajak/pengaturan_outlet diupsert',
    () async {
      api.pullResponse = const SyncPullResult(
        waktuPull: '2026-01-01T00:00:00Z',
        produk: [],
        kategori: [],
        satuan: [],
        pajak: [],
        promo: [],
        metodeBayar: [],
        stok: [],
        hargaOutlet: [
          {
            'id': 'ho-1',
            'outlet_id': 'outlet-asli',
            'produk_id': 'produk-1',
            'varian_id': null,
            'harga_jual': '9000.00',
            'updated_at': '2026-01-01T00:00:00Z',
            'deleted_at': null,
          },
        ],
        hargaGrosir: [
          {
            'id': 'hg-1',
            'produk_id': 'produk-1',
            'varian_id': null,
            'outlet_id': null,
            'min_qty': '10.0',
            'harga': '8500.00',
            'updated_at': '2026-01-01T00:00:00Z',
            'deleted_at': null,
          },
        ],
        tipeOrderPajak: [
          {'tipe_order_id': 'to-1', 'pajak_id': 'pajak-1'},
        ],
        pengaturanOutlet: [
          {
            'outlet_id': 'outlet-asli',
            'header_struk': null,
            'footer_struk': null,
            'tampil_logo': true,
            'lebar_kertas_mm': 58,
            'pembulatan': 500,
            'izinkan_stok_minus': true,
            'wajib_buka_shift': true,
            'struk_ringkas': false,
            'pakai_nomor_antrean': false,
            'updated_at': '2026-01-01T00:00:00Z',
            'deleted_at': null,
          },
        ],
        hasMore: {},
        paket: null,
        kodeFitur: [],
        batasFitur: {},
      );

      final hasil = await repo.jalankan();
      expect(hasil.jumlahDiterimaPull, 4);

      final hargaOutlet = await db.hargaDao.hargaOutletUntukOutlet(
        'outlet-asli',
      );
      expect(hargaOutlet.single.hargaJual, 9000);

      final hargaGrosir = await db.hargaDao.hargaGrosirUntukProduk([
        'produk-1',
      ]);
      expect(hargaGrosir.single.harga, 8500);
      expect(hargaGrosir.single.minQty, 10.0);

      final tipeOrderPajak = await db.tipeOrderDao.semuaTipeOrderPajak();
      expect(tipeOrderPajak.single.tipeOrderId, 'to-1');

      final pengaturan = await db.hargaDao.ambilPengaturanOutlet('outlet-asli');
      expect(pengaturan!.pembulatan, 500);
    },
  );

  // --- Perbaikan bug uji manual 2026-11-08 (BUG-010) ---
  SyncPullResult pullKosong() => const SyncPullResult(
        waktuPull: '2026-01-01T00:00:00Z',
        produk: [],
        kategori: [],
        satuan: [],
        pajak: [],
        promo: [],
        metodeBayar: [],
        stok: [],
        hargaOutlet: [],
        hargaGrosir: [],
        tipeOrderPajak: [],
        pengaturanOutlet: [],
        hasMore: {},
        paket: null,
        kodeFitur: [],
        batasFitur: {},
      );

  Future<void> sisipTransaksi(
    String id, {
    required TransaksiStatus status,
    int totalBayar = 0,
    String? metodeBayarId,
  }) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await db.into(db.transaksi).insert(
          TransaksiCompanion.insert(
            id: id,
            tokoId: 'toko-asli',
            outletId: 'outlet-asli',
            penggunaId: 'pengguna-asli',
            nomorStruk: status == TransaksiStatus.tersimpan ? 'DRAFT$now' : 'OUT1-$id',
            tanggal: now,
            status: status,
            total: const Value(15000),
            totalBayar: Value(totalBayar),
            createdAt: now,
            updatedAt: now,
          ),
        );
    if (metodeBayarId != null) {
      await db.into(db.pembayaran).insert(
            PembayaranCompanion.insert(
              id: 'bayar-$id',
              transaksiId: id,
              metodeBayarId: metodeBayarId,
              jumlah: totalBayar,
              status: PembayaranStatus.berhasil,
              createdAt: now,
              updatedAt: now,
            ),
          );
    }
  }

  Future<void> sisipMetodeTunai(String id) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await db.into(db.metodeBayar).insert(
          MetodeBayarCompanion.insert(
            id: id,
            tokoId: 'toko-asli',
            nama: 'Tunai',
            tipe: MetodeBayarTipe.tunai,
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  test('push: pesanan tersimpan (draft) tidak ikut terkirim sehingga transaksi selesai tidak tertahan', () async {
    await sisipMetodeTunai('metode-uuid-1');
    await sisipTransaksi('trx-selesai', status: TransaksiStatus.selesai, totalBayar: 15000, metodeBayarId: 'metode-uuid-1');
    await sisipTransaksi('trx-draft', status: TransaksiStatus.tersimpan);
    api.pullResponse = pullKosong();

    final hasil = await repo.jalankan();

    expect(hasil.transaksiTerkirim, 1);
    expect(api.transaksiDiterima.map((t) => t['id']), ['trx-selesai']);
    final draft = await (db.select(db.transaksi)..where((t) => t.id.equals('trx-draft'))).getSingle();
    expect(draft.disinkronPada, isNull, reason: 'draft tetap lokal, tidak ditandai tersinkron');
  });

  test('push: transaksi tanpa pembayaran (kasbon murni) memakai ID metode tunai asli, bukan placeholder', () async {
    await sisipMetodeTunai('metode-uuid-asli');
    await sisipTransaksi('trx-kasbon', status: TransaksiStatus.selesai, totalBayar: 0);
    api.pullResponse = pullKosong();

    await repo.jalankan();

    expect(api.transaksiDiterima.single['metode_bayar_id'], 'metode-uuid-asli');
  });

  test('push: nomor antrian ikut terkirim ke backend, dan dihilangkan bila antrian mati', () async {
    await sisipMetodeTunai('metode-uuid-1');
    await sisipTransaksi('trx-antre', status: TransaksiStatus.selesai, totalBayar: 15000, metodeBayarId: 'metode-uuid-1');
    await (db.update(db.transaksi)..where((t) => t.id.equals('trx-antre')))
        .write(const TransaksiCompanion(nomorAntrean: Value('A-005')));
    await sisipTransaksi('trx-tanpa', status: TransaksiStatus.selesai, totalBayar: 15000, metodeBayarId: 'metode-uuid-1');
    api.pullResponse = pullKosong();

    await repo.jalankan();

    final antre = api.transaksiDiterima.firstWhere((t) => t['id'] == 'trx-antre');
    final tanpa = api.transaksiDiterima.firstWhere((t) => t['id'] == 'trx-tanpa');
    expect(antre['nomor_antrean'], 'A-005');
    expect(tanpa.containsKey('nomor_antrean'), isFalse);
  });

  test('push: transaksi yang ditolak server tetap menunggu dan dikirim ulang; yang diterima tidak dikirim lagi', () async {
    await sisipMetodeTunai('metode-uuid-1');
    await sisipTransaksi('trx-ok', status: TransaksiStatus.selesai, totalBayar: 15000, metodeBayarId: 'metode-uuid-1');
    await sisipTransaksi('trx-tolak', status: TransaksiStatus.selesai, totalBayar: 15000, metodeBayarId: 'metode-uuid-1');
    api.idDitolak = {'trx-tolak'};
    api.pullResponse = pullKosong();

    final hasil = await repo.jalankan();
    expect(hasil.transaksiTerkirim, 1);
    expect(hasil.transaksiDitolak, 1);
    final pending = await db.transaksiDao.transaksiBelumSync();
    expect(pending.map((t) => t.id), ['trx-tolak'], reason: 'yang ditolak tidak boleh ditandai tersinkron');

    // Sync berikutnya: hanya yang ditolak yang dikirim lagi, tidak ada duplikat yang diterima.
    api.pullResponse = pullKosong();
    await repo.jalankan();
    expect(api.transaksiDiterima.map((t) => t['id']), ['trx-tolak']);

    // Penyebab penolakan hilang -> diterima, lalu tidak dikirim lagi.
    api.idDitolak = {};
    api.pullResponse = pullKosong();
    final hasil3 = await repo.jalankan();
    expect(hasil3.transaksiTerkirim, 1);
    expect(await db.transaksiDao.transaksiBelumSync(), isEmpty);
  });

  test('push: kas masuk/keluar milik shift yang dikirim ikut terkirim, lengkap dengan jenis dan jumlah', () async {
    await sisipMetodeTunai('metode-uuid-1');
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await db.into(db.shift).insert(ShiftCompanion.insert(
          id: 'shift-kas',
          tokoId: 'toko-asli',
          outletId: 'outlet-asli',
          penggunaId: 'pengguna-asli',
          dibukaPada: now,
          modalAwal: const Value(100000),
          status: ShiftStatus.buka,
          createdAt: now,
          updatedAt: now,
        ));
    await db.shiftDao.catatKasMasukKeluar(shiftId: 'shift-kas', jenis: KasShiftJenis.masuk, jumlah: 20000, keterangan: 'Tambah modal');
    await db.shiftDao.catatKasMasukKeluar(shiftId: 'shift-kas', jenis: KasShiftJenis.keluar, jumlah: 5000, keterangan: 'Beli es');
    api.pullResponse = pullKosong();

    await repo.jalankan();

    expect(api.shiftDiterima.single['id'], 'shift-kas');
    final kas = api.kasShiftDiterima;
    expect(kas.map((k) => (k['jenis'], k['jumlah'], k['keterangan'], k['shift_id'])), [
      ('masuk', '20000', 'Tambah modal', 'shift-kas'),
      ('keluar', '5000', 'Beli es', 'shift-kas'),
    ]);
  });

  test('jalankan: panggilan yang datang saat sync masih berjalan menunggu hasil yang sama (tidak ada push/pull ganda)', () async {
    await sisipMetodeTunai('metode-uuid-1');
    await sisipTransaksi('trx-sf', status: TransaksiStatus.selesai, totalBayar: 15000, metodeBayarId: 'metode-uuid-1');
    api.pullResponse = pullKosong();

    final pertama = repo.jalankan();
    final kedua = repo.jalankan();
    expect(identical(pertama, kedua), isTrue);
    final hasil = await pertama;
    expect(hasil.transaksiTerkirim, 1);
    expect((await kedua).transaksiTerkirim, 1);

    // Setelah selesai, panggilan berikutnya memulai sync baru (tidak macet pada hasil lama).
    api.pullResponse = pullKosong();
    final ketiga = repo.jalankan();
    expect(identical(pertama, ketiga), isFalse);
    await ketiga;
  });

  test('push: shift yang dirujuk transaksi ikut terkirim (kalau tidak, server menolak transaksinya)', () async {
    await sisipMetodeTunai('metode-uuid-1');
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await db.into(db.shift).insert(ShiftCompanion.insert(
          id: 'shift-lama',
          tokoId: 'toko-asli',
          outletId: 'outlet-asli',
          penggunaId: 'pengguna-asli',
          dibukaPada: now - 30 * 86400000,
          ditutupPada: Value(now - 30 * 86400000 + 3600000),
          modalAwal: const Value(100000),
          kasAktual: const Value(115000),
          status: ShiftStatus.tutup,
          createdAt: now - 30 * 86400000,
          updatedAt: now - 30 * 86400000,
        ));
    await sisipTransaksi('trx-sh', status: TransaksiStatus.selesai, totalBayar: 15000, metodeBayarId: 'metode-uuid-1');
    await (db.update(db.transaksi)..where((t) => t.id.equals('trx-sh')))
        .write(const TransaksiCompanion(shiftId: Value('shift-lama')));
    api.pullResponse = pullKosong();

    await repo.jalankan();

    final s = api.shiftDiterima.single;
    expect(s['id'], 'shift-lama');
    expect(s['status'], 'tutup');
    expect(s['modal_awal'], '100000');
    expect(s['kas_aktual'], '115000');
    expect(s.containsKey('ditutup_pada'), isTrue);
  });

  test('push: status pesanan awal ikut payload transaksi (nama sama dengan kode backend)', () async {
    await sisipMetodeTunai('metode-uuid-1');
    await sisipTransaksi('trx-s1', status: TransaksiStatus.selesai, totalBayar: 15000, metodeBayarId: 'metode-uuid-1');
    await (db.update(db.transaksi)..where((t) => t.id.equals('trx-s1')))
        .write(const TransaksiCompanion(statusPesanan: Value(StatusPesanan.diproses)));
    await sisipTransaksi('trx-s2', status: TransaksiStatus.selesai, totalBayar: 15000, metodeBayarId: 'metode-uuid-1');
    api.pullResponse = pullKosong();

    await repo.jalankan();

    final s1 = api.transaksiDiterima.firstWhere((t) => t['id'] == 'trx-s1');
    final s2 = api.transaksiDiterima.firstWhere((t) => t['id'] == 'trx-s2');
    expect(s1['status_pesanan'], 'diproses');
    expect(s2.containsKey('status_pesanan'), isFalse, reason: 'fitur status pesanan mati = tidak dikirim');
  });

  test('push: status pesanan ikut payload dan perubahannya dikirim sekali setelah transaksi tersync', () async {
    await sisipMetodeTunai('metode-uuid-1');
    await sisipTransaksi('trx-s3', status: TransaksiStatus.selesai, totalBayar: 15000, metodeBayarId: 'metode-uuid-1');
    await (db.update(db.transaksi)..where((t) => t.id.equals('trx-s3')))
        .write(const TransaksiCompanion(statusPesanan: Value(StatusPesanan.baru)));
    api.pullResponse = pullKosong();

    // Sync pertama: transaksi terkirim dengan status awal; tidak ada perubahan terpisah.
    await repo.jalankan();
    expect(api.transaksiDiterima.single['status_pesanan'], 'baru');
    expect(api.statusPesananDiterima, isEmpty);

    // Pelayan memajukan status SETELAH tersync -> dikirim lewat daftar status_pesanan.
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await db.transaksiDao.ubahStatusPesanan('trx-s3', StatusPesanan.siap, DateTime.now().toUtc().millisecondsSinceEpoch);
    api.pullResponse = pullKosong();
    await repo.jalankan();
    expect(api.statusPesananDiterima, [
      {'id': 'trx-s3', 'status': 'siap'},
    ]);

    // Sync berikutnya tidak mengirim ulang (fake hanya menimpa saat dipanggil,
    // jadi dikosongkan dulu; tanpa perubahan baru, syncPush tidak dipanggil sama sekali).
    api.statusPesananDiterima = [];
    api.pullResponse = pullKosong();
    await repo.jalankan();
    expect(api.statusPesananDiterima, isEmpty);
  });
}
