import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../struk/logo_cache.dart';
import '../../features/fitur/data/local/fitur_dao.dart';
import 'api_config.dart';
import '../../features/order/data/local/tipe_order_dao.dart';
import '../../features/pelanggan/data/local/pelanggan_dao.dart';
import '../../features/produk/data/local/harga_dao.dart';
import '../../features/produk/data/local/produk_dao.dart';
import '../../features/produk/data/local/satuan_dao.dart';
import '../../features/produk/data/local/tables/produk_table.dart';
import '../../features/pelanggan/domain/ulang_tahun.dart';
import '../../features/promo/data/local/pajak_dao.dart';
import '../../features/promo/data/local/promo_dao.dart';
import '../../features/promo/data/local/tables/pajak_table.dart';
import '../../features/promo/data/local/tables/promo_table.dart';
import '../../features/stok/data/local/stok_dao.dart';
import '../../features/transaksi/data/local/metode_bayar_dao.dart';
import '../../features/transaksi/data/local/tables/metode_bayar_table.dart';
import '../../features/transaksi/data/local/transaksi_dao.dart';
import '../database/app_database.dart';
import '../database/pengguna_dao.dart';
import '../providers/database_provider.dart';
import '../providers/session_provider.dart';
import 'auth_session_store.dart';
import 'backend_api.dart';
import 'backend_exception.dart';
import 'dio_backend_api.dart';
import 'sync_mapping.dart';

class HasilSync {
  const HasilSync({
    required this.transaksiTerkirim,
    required this.transaksiDitolak,
    required this.jumlahDiterimaPull,
  });

  final int transaksiTerkirim;
  final int transaksiDitolak;
  final int jumlahDiterimaPull;
}

const _hariMs = 86400000;

/// Push transaksi yg belum sync + pull data master (produk/kategori/satuan/
/// pajak/promo/metode_bayar/stok/pengguna/role/role_izin) dari backend.
/// Sengaja TIDAK push shift/kas_shift/pelanggan (belum ada kolom watermark
/// "sudah disinkron" yg setara `transaksi.disinkronPada` utk tabel2 itu) -
/// dicatat sbg susulan, bukan lupa. Pull pengguna/role/role_izin (tahap
/// 5b, "satukan identitas karyawan") TIDAK butuh strategi merge rumit lagi
/// spt dulu dikhawatirkan - karyawan SELALU dibuat di server dulu (lihat
/// PenggunaFormPage online), jadi `id` yang di-pull SELALU id server asli,
/// aman di-insertOnConflictUpdate apa adanya (bukan sekadar "cache", ini
/// BENAR identitas device pakai sampai karyawan itu dihapus/dinonaktifkan).
class SyncRepository {
  SyncRepository({
    required this.api,
    required this.sessionStore,
    required this.transaksiDao,
    required this.produkDao,
    required this.satuanDao,
    required this.pajakDao,
    required this.promoDao,
    required this.metodeBayarDao,
    required this.stokDao,
    required this.fiturDao,
    required this.hargaDao,
    required this.tipeOrderDao,
    required this.penggunaDao,
    required this.pelangganDao,
    this.metodeBayarTunaiFallback = 'metode-tunai-default',
    this.baseUrl = '',
  });

  final BackendApi api;
  final AuthSessionStore sessionStore;
  final TransaksiDao transaksiDao;
  final ProdukDao produkDao;
  final SatuanDao satuanDao;
  final PajakDao pajakDao;
  final PromoDao promoDao;
  final MetodeBayarDao metodeBayarDao;
  final StokDao stokDao;
  final FiturDao fiturDao;
  final HargaDao hargaDao;
  final TipeOrderDao tipeOrderDao;
  final PenggunaDao penggunaDao;
  // Modul 10 - lihat catatan `pelanggan` di SyncPullResult (backend_api.dart)
  // kenapa pull pelanggan ini wajib ada (poin/total_belanja basi tanpanya).
  final PelangganDao pelangganDao;
  // Dipakai SATU-SATUNYA utk mengisi `metode_bayar_id` (field WAJIB di
  // body checkout backend) saat push transaksi kasbon murni (totalBayar
  // 0 di awal) - tidak ada baris Pembayaran lokal sama sekali utk diambil
  // metode_bayar_id-nya (sama konvensi dgn backend: 0 DP = tidak ada baris
  // pembayaran, "metode" belum berarti apa2 krn belum ada uang berpindah).
  final String metodeBayarTunaiFallback;
  // Dipakai utk resolve logo_url yang berupa path relatif ("/static/logo/..")
  // saat backend belum pakai S3 (development) - URL absolut (S3/R2) dipakai
  // apa adanya, lihat _cacheLogo.
  final String baseUrl;

  Future<HasilSync>? _sedangJalan;

  /// Satu sync pada satu waktu: pemanggil yang datang saat sync masih berjalan (tombol manual,
  /// sync otomatis, simpan pengaturan) menunggu hasil yang sama, bukan memulai push/pull kedua
  /// yang berebut menandai transaksi dan menimpa kursor pull.
  Future<HasilSync> jalankan({String? outletId}) {
    final aktif = _sedangJalan;
    if (aktif != null) return aktif;
    final hasil = _jalankanSekali(outletId: outletId).whenComplete(() => _sedangJalan = null);
    return _sedangJalan = hasil;
  }

  Future<HasilSync> _jalankanSekali({String? outletId}) async {
    final sesi = await sessionStore.muat();
    if (sesi == null) {
      throw const BackendException(message: 'Device belum pairing ke backend');
    }

    final (terkirim, ditolak) = await _push(sesi);
    final diterima = await _pull(sesi, outletId: outletId);
    await _reconcileMetodeBayar(sesi);
    return HasilSync(
      transaksiTerkirim: terkirim,
      transaksiDitolak: ditolak,
      jumlahDiterimaPull: diterima,
    );
  }

  /// Bersihkan metode bayar "hantu" (lihat
  /// MetodeBayarDao.hapusSelainIdServer) - WAJIB pakai daftar PENUH
  /// `GET /metode-bayar`, BUKAN hasil `/sync/pull` yang cuma kirim baris
  /// berubah sejak `since` (delta) - kalau dipakai di _terapkanPull/per
  /// halaman pull, baris lama yang kebetulan tidak berubah sejak sync
  /// terakhir bisa salah ikut terhapus. Best-effort (dibungkus try/catch
  /// total, pola sama dgn _cacheLogo) - gagal di sini TIDAK BOLEH
  /// menggagalkan push+pull yang jauh lebih penting.
  Future<void> _reconcileMetodeBayar(SesiBackend sesi) async {
    try {
      final rows = await api.getJson(accessToken: sesi.accessToken, path: '/metode-bayar');
      final idDariServer = (rows as List).cast<Map<String, dynamic>>().map((r) => r['id'] as String).toList();
      await metodeBayarDao.hapusSelainIdServer(tokoId: sesi.tokoId, idDariServer: idDariServer);
    } catch (_) {
      // Diam2 dilewati - lihat komentar di atas.
    }
  }

  Future<(int, int)> _push(SesiBackend sesi) async {
    final belumSync = await transaksiDao.transaksiBelumSync();
    if (belumSync.isEmpty) {
      await _pushStandalone(sesi);
      return (0, 0);
    }

    // Transaksi tanpa baris Pembayaran (kasbon murni) tetap WAJIB membawa
    // metode_bayar_id berbentuk UUID. Pakai ID metode tunai asli toko ini;
    // placeholder lama hanya cadangan terakhir.
    final metodeTunaiId = await metodeBayarDao.idMetodeTunai(sesi.tokoId) ?? metodeBayarTunaiFallback;

    final payload = <Map<String, dynamic>>[];
    for (final t in belumSync) {
      final items = await transaksiDao.itemUntukTransaksiList([t.id]);
      // Varian/tambahan yang dipilih tiap item (IMOGI no. 42). harga_satuan di bawah
      // sudah HARGA AKHIR termasuk tambahan; server menyimpan modifier apa adanya.
      final modifierRows = await transaksiDao.modifierUntukItemList([for (final i in items) i.id]);
      final pembayaranList = await transaksiDao.pembayaranUntukTransaksiList([
        t.id,
      ]);
      // Temuan#1 (rapikan F3) - FIX: sebelumnya pakai promoUntukTransaksi()
      // (max 1 baris via getSingleOrNull) - transaksi dgn diskon member
      // DAN promo kode sekaligus (2 baris TransaksiPromo) bikin push ini
      // CRASH (StateError) sebelum perbaikan ini, lihat transaksi_dao.dart.
      final promoRows = await transaksiDao.semuaPromoUntukTransaksi(t.id);
      final promoAsli = promoRows.where((p) => p.promoId != null).firstOrNull;
      final pajakRows = await transaksiDao.pajakUntukTransaksi(t.id);
      // Kasbon murni (totalBayar 0 di awal) sengaja TIDAK punya baris
      // Pembayaran sama sekali (lihat TransaksiRepository.checkout) - itu
      // valid, BUKAN "ganjil" lagi sejak tahap 3b-1 (dulu transaksi tanpa
      // pembayaran dilewati di sini krn sebelumnya memang selalu berarti
      // state korup/separuh-jadi).

      // Tahap 5b (desain #4/#5) - karyawan yang SEBENARNYA login di HP
      // saat transaksi ini dibuat, BUKAN token device/Owner yang mengirim
      // push ini (satu token dipakai bergilir sepanjang hari). null kalau
      // karyawan ini belum diketahui id server-nya sama sekali (belum
      // pernah sync/migrasi) - server fallback ke identitas token-nya
      // sendiri drpd field ini, perilaku lama tetap jalan.
      final penggunaLokal = await penggunaDao.cariById(t.penggunaId);
      final penggunaIdServer = penggunaLokal?.serverPenggunaId;

      payload.add({
        'id': t.id,
        'outlet_id': t.outletId,
        if (penggunaIdServer != null) 'pengguna_id': penggunaIdServer,
        if (t.shiftId != null) 'shift_id': t.shiftId,
        if (t.pelangganId != null) 'pelanggan_id': t.pelangganId,
        if (t.tipeOrderId != null) 'tipe_order_id': t.tipeOrderId,
        if (t.mejaId != null) 'meja_id': t.mejaId,
        'nomor_struk': t.nomorStruk,
        if (t.nomorAntrean != null) 'nomor_antrean': t.nomorAntrean,
        if (t.statusPesanan != null) 'status_pesanan': t.statusPesanan!.name,
        'tanggal': DateTime.fromMillisecondsSinceEpoch(
          t.tanggal,
          isUtc: true,
        ).toIso8601String(),
        'items': items
            .map(
              (i) => {
                'produk_id': i.produkId,
                if (i.varianId != null) 'varian_id': i.varianId,
                'nama_produk': i.namaProduk,
                'qty': i.qty.toString(),
                'harga_satuan': i.hargaSatuan.toString(),
                'hpp_satuan': i.hppSatuan.toString(),
                'diskon': i.diskon.toString(),
                'modifiers': [
                  for (final m in modifierRows)
                    if (m.itemTransaksiId == i.id)
                      {
                        if (m.modifierId != null) 'modifier_id': m.modifierId,
                        'nama': m.nama,
                        'harga': m.harga.toString(),
                      },
                ],
              },
            )
            .toList(),
        if (promoAsli != null) 'promo_id': promoAsli.promoId,
        'metode_bayar_id': pembayaranList.isNotEmpty
            ? pembayaranList.first.metodeBayarId
            : metodeTunaiId,
        'total_bayar': t.totalBayar.toString(),
        // Split payment (F3.A) - kirim SEMUA baris Pembayaran lokal transaksi
        // ini (bukan cuma field metode_bayar_id/total_bayar di atas yang
        // cuma mewakili baris pertama) - ini satu2nya jalan ref_gateway/
        // payload_gateway ikut terkirim, termasuk kasus 1 baris non-tunai
        // (Kartu/Transfer/QRIS tanpa split beneran).
        //
        // Temuan A.1 (tahap 5) - FIX: sebelumnya cuma meng-ekstrak key
        // 'empat_digit_akhir_kartu' dari payloadGateway lokal, jadi
        // penanda QRIS manual (`{"metode":"qris_statis_manual",...}`,
        // lihat BayarQrisPage) DIBUANG diam2 krn tidak punya key itu.
        // Sekarang kirim SELURUH objek JSON apa adanya sbg `payload_gateway` -
        // backend (checkout_service.py) sudah terima field generik ini dan
        // memakainya APA ADANYA (menang drpd fallback empat_digit_akhir_kartu).
        if (pembayaranList.isNotEmpty)
          'split_pembayaran': [
            for (final p in pembayaranList)
              {
                'metode_bayar_id': p.metodeBayarId,
                'jumlah': p.jumlah.toString(),
                if (p.refGateway != null) 'nomor_referensi': p.refGateway,
                if (p.payloadGateway != null)
                  'payload_gateway': jsonDecode(p.payloadGateway!),
              },
          ],
        if (t.catatan != null) 'catatan': t.catatan,
        // Kasbon (tahap 3b-1) - backend menghitung ULANG status_bayar/
        // sisa_tagihan sendiri dari total_bayar vs total (sama formula
        // dgn TransaksiRepository.checkout di sini), cuma jatuh_tempo_hari
        // yang perlu dikirim supaya due date-nya sama persis dgn yang
        // kasir pilih di BayarKasbonPage (default 7 hari di kedua sisi
        // kalau tidak dikirim).
        if (t.jatuhTempo != null)
          'jatuh_tempo_hari': ((t.jatuhTempo! - t.tanggal) / _hariMs).round(),
        // Tahap 3a Part B/C.2 - angka yg SUDAH dihitung HP sendiri lewat
        // lib/core/harga/kalkulator.dart (sama persis dgn yg tersimpan di
        // kolom `transaksi` lokal ini) - server menyimpannya APA ADANYA
        // utk transaksi offline, cuma membandingkan dgn hitung ulangnya
        // sendiri utk audit_log (lihat checkout_service.py).
        'subtotal_klien': t.subtotal.toString(),
        'total_diskon_klien': t.totalDiskon.toString(),
        'total_pajak_klien': t.totalPajak.toString(),
        'pembulatan_klien': t.pembulatan.toString(),
        'total_klien': t.total.toString(),
        // Modul 10 (tukar poin) - t.totalDiskon/t.total DI ATAS sudah
        // termasuk diskonPoin (lihat TransaksiRepository.checkout), dua
        // field di bawah ini CUMA supaya backend tahu berapa POIN yg
        // harus dikurangi dari pelanggan.poin (bukan ikut mengubah
        // total lagi - lihat checkout_service.py bagian is_push_offline).
        if (t.poinDitukar > 0) 'poin_ditukar': t.poinDitukar,
        if (t.poinDitukar > 0) 'diskon_poin_klien': t.diskonPoin.toString(),
        // Temuan#1 (rapikan F3) - rincian per-baris pajak/service & promo/
        // member yang sudah dihitung HP (lihat TransaksiRepository.checkout
        // yang sekarang mengisi pajakId lewat pencocokan nama+persen ke
        // master Pajak aktif saat checkout, lihat _cariPajakId) - server
        // simpan APA ADANYA ke transaksi_pajak/transaksi_promo, supaya
        // refund proporsional & laporan per-jenis konsisten dgn online.
        if (pajakRows.isNotEmpty)
          'rincian_pajak_klien': [
            for (final p in pajakRows)
              {
                if (p.pajakId != null) 'pajak_id': p.pajakId,
                'nama': p.nama,
                'persen': p.persen.toString(),
                'jumlah': p.jumlah.toString(),
              },
          ],
        if (promoRows.isNotEmpty)
          'rincian_promo_klien': [
            for (final p in promoRows)
              {
                if (p.promoId != null) 'promo_id': p.promoId,
                'nama': p.nama,
                'jumlah_diskon': p.jumlahDiskon.toString(),
              },
          ],
        // Temuan A.2 (tahap 5) - snapshot struk (lihat
        // lib/core/struk/struk_snapshot.dart, diisi StrukPage tepat
        // setelah checkout) ikut dikirim apa adanya, supaya HP LAIN bisa
        // cetak ulang identik lewat GET /transaksi/{id} (lihat
        // TransaksiDetailPage._ambilSnapshotDariServer).
        if (t.snapshotStruk != null) 'snapshot_struk': jsonDecode(t.snapshotStruk!),
      });
    }

    final pembayaranPayload = await _pembayaranStandalonePayload();
    final pesananBatalPayload = await _pesananBatalPayload();
    final statusPesananPayload = await _statusPesananPayload();
    final shiftPayload = await _shiftPayload({for (final t in belumSync) ?t.shiftId});
    final kasShiftPayload = await _kasShiftPayload(shiftPayload);
    final hasil = await api.syncPush(
      accessToken: sesi.accessToken,
      perangkatId: sesi.perangkatId,
      transaksi: payload,
      shift: shiftPayload,
      kasShift: kasShiftPayload,
      pembayaran: pembayaranPayload,
      pesananBatal: pesananBatalPayload,
      statusPesanan: statusPesananPayload,
    );

    final sukses = <String>[];
    var ditolak = 0;
    for (final item in hasil.transaksi) {
      if (item.status == 'ditolak') {
        ditolak++;
      } else {
        sukses.add(item.id);
      }
    }
    if (sukses.isNotEmpty) {
      await transaksiDao.tandaiSudahSync(
        sukses,
        DateTime.now().toUtc().millisecondsSinceEpoch,
      );
    }
    await _tandaiPembayaranSukses(hasil.pembayaran);
    await _tandaiPesananBatalSukses(hasil.pesananBatal);
    await _tandaiStatusPesananSukses(hasil.statusPesanan);
    return (sukses.length, ditolak);
  }

  /// Cicilan/pelunasan kasbon yang dicatat BELAKANGAN (transaksi induknya
  /// bisa saja sudah tersync sebelumnya, beda dgn pembayaran yang lahir
  /// bersama checkout - lihat komentar Pembayaran.disinkronPada) - dipush
  /// lewat kategori `pembayaran` tersendiri di /sync/push, TIDAK ikut
  /// payload `transaksi` di atas.
  Future<List<Map<String, dynamic>>> _pembayaranStandalonePayload() async {
    final belum = await transaksiDao.pembayaranBelumSync();
    return [
      for (final p in belum)
        {
          'id': p.id,
          'transaksi_id': p.transaksiId,
          if (p.shiftId != null) 'shift_id': p.shiftId,
          'metode_bayar_id': p.metodeBayarId,
          'jumlah': p.jumlah.toString(),
          if (p.dibayarPada != null)
            'dibayar_pada': DateTime.fromMillisecondsSinceEpoch(
              p.dibayarPada!,
              isUtc: true,
            ).toIso8601String(),
          // Temuan A.1 (tahap 5) - pelunasan/cicilan kasbon yang dibayar
          // pakai QRIS statis (lihat pelunasan_page.dart) juga wajib ikut
          // mengirim penandanya, sama pola dgn split_pembayaran di atas.
          if (p.payloadGateway != null) 'payload_gateway': jsonDecode(p.payloadGateway!),
        },
    ];
  }

  Future<void> _tandaiPembayaranSukses(List<HasilPushItem> hasil) async {
    final sukses = [for (final h in hasil) if (h.status != 'ditolak') h.id];
    if (sukses.isNotEmpty) {
      await transaksiDao.tandaiPembayaranSudahSync(
        sukses,
        DateTime.now().toUtc().millisecondsSinceEpoch,
      );
    }
  }

  /// Temuan#2 (rapikan F3.E) - pembatalan pesanan tersimpan yang terjadi
  /// SAAT OFFLINE, dicatat lokal dulu lewat
  /// TransaksiRepository.batalkanPesanan (draft-nya sendiri sudah dihapus
  /// lokal SEBELUM ini, jadi baris ini SNAPSHOT isi/total) - dipush lewat
  /// kategori `pesanan_batal` tersendiri di /sync/push.
  Future<List<Map<String, dynamic>>> _pesananBatalPayload() async {
    final belum = await transaksiDao.pembatalanPesananBelumSync();
    final hasil = <Map<String, dynamic>>[];
    for (final p in belum) {
      final penggunaLokal = p.penggunaId == null ? null : await penggunaDao.cariById(p.penggunaId!);
      hasil.add({
        'id': p.id,
        'alasan': p.alasan,
        if (p.disetujuiOleh != null) 'disetujui_oleh': p.disetujuiOleh,
        if (penggunaLokal?.serverPenggunaId != null) 'pengguna_id': penggunaLokal!.serverPenggunaId,
      });
    }
    return hasil;
  }

  Future<void> _tandaiPesananBatalSukses(List<HasilPushItem> hasil) async {
    final sukses = [for (final h in hasil) if (h.status != 'ditolak') h.id];
    if (sukses.isNotEmpty) {
      await transaksiDao.tandaiPembatalanPesananSudahSync(
        sukses,
        DateTime.now().toUtc().millisecondsSinceEpoch,
      );
    }
  }

  /// Dipanggil saat TIDAK ada transaksi baru yg perlu dipush sama sekali -
  /// tetap wajib cek+push cicilan/pelunasan + pembatalan pesanan standalone,
  /// jangan diam2 terlewat cuma krn tidak ada transaksi baru di batch ini.
  Future<void> _pushStandalone(SesiBackend sesi) async {
    final payload = await _pembayaranStandalonePayload();
    final pesananBatalPayload = await _pesananBatalPayload();
    final statusPesananPayload = await _statusPesananPayload();
    final shiftPayload = await _shiftPayload(const {});
    final kasShiftPayload = await _kasShiftPayload(shiftPayload);
    if (payload.isEmpty && pesananBatalPayload.isEmpty && statusPesananPayload.isEmpty && shiftPayload.isEmpty) return;

    final hasil = await api.syncPush(
      accessToken: sesi.accessToken,
      perangkatId: sesi.perangkatId,
      transaksi: const [],
      shift: shiftPayload,
      kasShift: kasShiftPayload,
      pembayaran: payload,
      pesananBatal: pesananBatalPayload,
      statusPesanan: statusPesananPayload,
    );
    await _tandaiPembayaranSukses(hasil.pembayaran);
    await _tandaiPesananBatalSukses(hasil.pesananBatal);
    await _tandaiStatusPesananSukses(hasil.statusPesanan);
  }

  /// Shift buat/tutup di HP. Tanpa ini server tidak punya shiftnya dan menolak transaksi
  /// yang merujuknya ("Shift tidak ditemukan"). Dikirim: yang dirujuk transaksi belum-sync,
  /// yang masih buka, dan yang berubah 2 hari terakhir (server idempoten).
  Future<List<Map<String, dynamic>>> _shiftPayload(Set<String> idDirujuk) async {
    final sejak = DateTime.now().toUtc().millisecondsSinceEpoch - 2 * _hariMs;
    final rows = await transaksiDao.attachedDatabase.shiftDao.shiftUntukSync(idDirujuk: idDirujuk, sejakMs: sejak);
    final hasil = <Map<String, dynamic>>[];
    for (final s in rows) {
      final pengguna = await penggunaDao.cariById(s.penggunaId);
      final idServer = pengguna?.serverPenggunaId;
      String iso(int ms) => DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toIso8601String();
      hasil.add({
        'id': s.id,
        'outlet_id': s.outletId,
        'dibuka_pada': iso(s.dibukaPada),
        if (s.ditutupPada != null) 'ditutup_pada': iso(s.ditutupPada!),
        'modal_awal': s.modalAwal.toString(),
        if (s.kasAktual != null) 'kas_aktual': s.kasAktual.toString(),
        if (s.catatan != null) 'catatan': s.catatan,
        'status': s.status.name,
        if (idServer != null) 'pengguna_id': idServer,
      });
    }
    return hasil;
  }

  /// Kas masuk/keluar milik shift yang ikut dikirim ([shiftPayload]). Tanpa ini kas yang
  /// seharusnya di server (modal + tunai + kas masuk - kas keluar) tidak sama dengan di HP.
  Future<List<Map<String, dynamic>>> _kasShiftPayload(List<Map<String, dynamic>> shiftPayload) async {
    final idShift = [for (final s in shiftPayload) s['id'] as String];
    final rows = await transaksiDao.attachedDatabase.shiftDao.kasUntukShift(idShift);
    final hasil = <Map<String, dynamic>>[];
    for (final k in rows) {
      final pengguna = k.dibuatOleh == null ? null : await penggunaDao.cariById(k.dibuatOleh!);
      final idServer = pengguna?.serverPenggunaId;
      hasil.add({
        'id': k.id,
        'shift_id': k.shiftId,
        'jenis': k.jenis.name,
        'jumlah': k.jumlah.toString(),
        'keterangan': k.keterangan,
        if (idServer != null) 'pengguna_id': idServer,
      });
    }
    return hasil;
  }

  /// Status pesanan yang berubah SETELAH transaksinya tersync. Yang transaksinya
  /// belum tersync tidak ikut sini: status terbarunya ikut payload transaksi.
  Future<List<Map<String, dynamic>>> _statusPesananPayload() async {
    final rows = await transaksiDao.statusPesananBelumSync();
    return [
      for (final r in rows) {'id': r.id, 'status': r.statusPesanan!.name},
    ];
  }

  Future<void> _tandaiStatusPesananSukses(List<HasilPushItem> hasil) async {
    // 'ditolak' (mis. transaksinya belum ada di server) dibiarkan supaya dicoba lagi.
    final sukses = [for (final h in hasil) if (h.status != 'ditolak') h.id];
    if (sukses.isNotEmpty) {
      await transaksiDao.tandaiStatusPesananSudahSync(sukses, DateTime.now().toUtc().millisecondsSinceEpoch);
    }
  }

  Future<int> _pull(SesiBackend sesi, {String? outletId}) async {
    var since = await sessionStore.ambilLastSyncAt();
    var totalDiterima = 0;
    String? logoUrlTerakhir;

    for (var iterasi = 0; iterasi < 50; iterasi++) {
      final hasil = await api.syncPull(
        accessToken: sesi.accessToken,
        perangkatId: sesi.perangkatId,
        since: since,
        outletId: outletId ?? sesi.outletId,
      );
      logoUrlTerakhir = hasil.logoUrl;

      await _terapkanPull(hasil, tokoId: sesi.tokoId);
      await fiturDao.simpanStatusFitur(
        tokoId: sesi.tokoId,
        paket: hasil.paket,
        kodeFiturAktif: hasil.kodeFitur,
        batasPerKode: hasil.batasFitur,
        updatedAt: DateTime.now().toUtc().millisecondsSinceEpoch,
      );
      totalDiterima +=
          hasil.produk.length +
          hasil.kategori.length +
          hasil.satuan.length +
          hasil.pajak.length +
          hasil.promo.length +
          hasil.metodeBayar.length +
          hasil.stok.length +
          hasil.hargaOutlet.length +
          hasil.hargaGrosir.length +
          hasil.tipeOrderPajak.length +
          hasil.pengaturanOutlet.length;

      final since_ = _majukanSince(since, hasil);
      final masihAda = hasil.hasMore.values.any((v) => v);
      if (!masihAda || since_ == since) {
        since = since_;
        break;
      }
      since = since_;
    }

    await sessionStore.simpanLastSyncAt(since);
    if (logoUrlTerakhir != null) await _cacheLogo(logoUrlTerakhir);
    return totalDiterima;
  }

  /// Unduh+cache logo toko (tahap 4 bagian C.6/D - LogoCache) supaya struk
  /// tetap bisa cetak logo saat device offline. Dibungkus try/catch
  /// SELURUHNYA - gagal unduh logo TIDAK BOLEH menggagalkan sync lainnya
  /// (produk/transaksi/dkk jauh lebih penting drpd logo kosmetik).
  Future<void> _cacheLogo(String logoUrl) async {
    try {
      final urlPenuh = logoUrl.startsWith('http') ? logoUrl : '$baseUrl$logoUrl';
      final dio = Dio();
      final resp = await dio.get<List<int>>(
        urlPenuh,
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = resp.data;
      if (bytes != null && bytes.isNotEmpty) {
        await LogoCache.simpan(bytes);
      }
    } catch (_) {
      // Diam2 dilewati - lihat komentar di atas.
    }
  }

  String _majukanSince(String sinceLama, SyncPullResult hasil) {
    var terbaru = DateTime.parse(sinceLama);
    for (final rows in [
      hasil.produk,
      hasil.kategori,
      hasil.satuan,
      hasil.pajak,
      hasil.promo,
      hasil.metodeBayar,
      hasil.stok,
      hasil.hargaOutlet,
      hasil.hargaGrosir,
      hasil.pengaturanOutlet,
      hasil.pelanggan,
      // tipe_order_pajak TIDAK disertakan - tabel relasi murni tanpa
      // kolom updated_at (selalu snapshot penuh, lihat _terapkanPull).
    ]) {
      for (final row in rows) {
        final updatedAt = DateTime.parse(row['updated_at'] as String);
        if (updatedAt.isAfter(terbaru)) terbaru = updatedAt;
      }
    }
    return terbaru.toIso8601String();
  }

  Future<void> _terapkanPull(
    SyncPullResult hasil, {
    required String tokoId,
  }) async {
    for (final row in hasil.kategori) {
      await produkDao.upsertKategori(
        KategoriCompanion.insert(
          id: row['id'] as String,
          tokoId: tokoId,
          nama: row['nama'] as String,
          warna: Value(row['warna'] as String?),
          urutan: Value(row['urutan'] as int? ?? 0),
          masukTiketDapur: Value(row['masuk_tiket_dapur'] as bool? ?? true),
          createdAt: epochMsDariBackend(row['updated_at'] as String),
          updatedAt: epochMsDariBackend(row['updated_at'] as String),
          deletedAt: Value(
            epochMsDariBackendNullable(row['deleted_at'] as String?),
          ),
        ),
      );
    }

    for (final row in hasil.satuan) {
      await satuanDao.upsertSatuan(
        SatuanCompanion.insert(
          id: row['id'] as String,
          tokoId: tokoId,
          nama: row['nama'] as String,
          singkatan: row['singkatan'] as String,
          createdAt: epochMsDariBackend(row['updated_at'] as String),
          updatedAt: epochMsDariBackend(row['updated_at'] as String),
          deletedAt: Value(
            epochMsDariBackendNullable(row['deleted_at'] as String?),
          ),
        ),
      );
    }

    for (final row in hasil.produk) {
      await produkDao.upsertProduk(
        ProdukCompanion.insert(
          id: row['id'] as String,
          tokoId: tokoId,
          kategoriId: Value(row['kategori_id'] as String?),
          satuanId: Value(row['satuan_id'] as String?),
          sku: Value(row['sku'] as String?),
          barcode: Value(row['barcode'] as String?),
          nama: row['nama'] as String,
          tipe: _produkTipeEnum(row['tipe'] as String),
          lacakStok: Value(row['lacak_stok'] as bool),
          hpp: Value(uangDariBackend(row['hpp'] as String)),
          hargaJual: Value(uangDariBackend(row['harga_jual'] as String)),
          aktif: Value(row['aktif'] as bool),
          createdAt: epochMsDariBackend(row['updated_at'] as String),
          updatedAt: epochMsDariBackend(row['updated_at'] as String),
          deletedAt: Value(
            epochMsDariBackendNullable(row['deleted_at'] as String?),
          ),
        ),
      );
    }

    for (final row in hasil.pajak) {
      await pajakDao.upsertPajak(
        PajakCompanion.insert(
          id: row['id'] as String,
          tokoId: tokoId,
          nama: row['nama'] as String,
          tipe: Value(_pajakTipeEnum(row['tipe'] as String)),
          persen: realDariBackend(row['persen'] as String),
          termasukHarga: Value(row['termasuk_harga'] as bool),
          urutan: Value(row['urutan'] as int? ?? 0),
          aktif: Value(row['aktif'] as bool),
          createdAt: epochMsDariBackend(row['updated_at'] as String),
          updatedAt: epochMsDariBackend(row['updated_at'] as String),
          deletedAt: Value(
            epochMsDariBackendNullable(row['deleted_at'] as String?),
          ),
        ),
      );
    }

    for (final row in hasil.promo) {
      await promoDao.upsertPromo(
        PromoCompanion.insert(
          id: row['id'] as String,
          tokoId: tokoId,
          nama: row['nama'] as String,
          kode: Value(row['kode'] as String?),
          tipe: _promoTipeEnum(row['tipe'] as String),
          nilai: realDariBackend(row['nilai'] as String),
          minBelanja: Value(uangDariBackend(row['min_belanja'] as String)),
          maksDiskon: Value(
            uangDariBackendNullable(row['maks_diskon'] as String?),
          ),
          aktif: Value(row['aktif'] as bool),
          khususUlangTahun: Value((row['khusus_ulang_tahun'] as bool?) ?? false),
          createdAt: epochMsDariBackend(row['updated_at'] as String),
          updatedAt: epochMsDariBackend(row['updated_at'] as String),
          deletedAt: Value(
            epochMsDariBackendNullable(row['deleted_at'] as String?),
          ),
        ),
      );
    }

    for (final row in hasil.metodeBayar) {
      await metodeBayarDao.upsertMetodeBayar(
        MetodeBayarCompanion.insert(
          id: row['id'] as String,
          tokoId: tokoId,
          nama: row['nama'] as String,
          tipe: _metodeBayarTipeEnum(row['tipe'] as String),
          butuhGateway: Value(row['butuh_gateway'] as bool),
          masukLaci: Value(row['masuk_laci'] as bool),
          aktif: Value(row['aktif'] as bool),
          createdAt: epochMsDariBackend(row['updated_at'] as String),
          updatedAt: epochMsDariBackend(row['updated_at'] as String),
          deletedAt: Value(
            epochMsDariBackendNullable(row['deleted_at'] as String?),
          ),
        ),
      );
    }

    for (final row in hasil.stok) {
      await stokDao.upsertSaldoDariSync(
        id: row['id'] as String,
        outletId: row['outlet_id'] as String,
        produkId: row['produk_id'] as String,
        varianId: row['varian_id'] as String?,
        jumlah: realDariBackend(row['jumlah'] as String),
        batasMinimum: realDariBackend(row['batas_minimum'] as String),
        hppRataRata: uangDariBackend(row['hpp_rata_rata'] as String),
        updatedAt: epochMsDariBackend(row['updated_at'] as String),
        deletedAt: epochMsDariBackendNullable(row['deleted_at'] as String?),
      );
    }

    for (final row in hasil.pelanggan) {
      // Field yg TIDAK dikirim backend (tanggal_lahir/level_member_id/
      // batas_kasbon/catatan - lihat sync_service.py kolom pelanggan)
      // SENGAJA tidak disentuh companion ini - insertOnConflictUpdate
      // cuma meng-update kolom yg benar2 diisi (Value.absent() lain
      // dibiarkan apa adanya), jadi field yg diisi lewat online-direct
      // CRUD lokal (pelanggan_form_page.dart) tidak ketimpa.
      await pelangganDao.upsertPelanggan(
        PelangganCompanion.insert(
          id: row['id'] as String,
          tokoId: tokoId,
          nama: row['nama'] as String,
          noHp: Value(row['no_hp'] as String?),
          email: Value(row['email'] as String?),
          tanggalLahir: Value(tanggalLahirDariIso(row['tanggal_lahir'] as String?)),
          poin: Value(row['poin'] as int),
          totalBelanja: Value(uangDariBackend(row['total_belanja'] as String)),
          createdAt: epochMsDariBackend(row['updated_at'] as String),
          updatedAt: epochMsDariBackend(row['updated_at'] as String),
          deletedAt: Value(
            epochMsDariBackendNullable(row['deleted_at'] as String?),
          ),
        ),
      );
    }

    for (final row in hasil.hargaOutlet) {
      await hargaDao.upsertHargaOutlet(
        HargaOutletCompanion.insert(
          id: row['id'] as String,
          outletId: row['outlet_id'] as String,
          produkId: row['produk_id'] as String,
          varianId: Value(row['varian_id'] as String?),
          hargaJual: uangDariBackend(row['harga_jual'] as String),
          createdAt: epochMsDariBackend(row['updated_at'] as String),
          updatedAt: epochMsDariBackend(row['updated_at'] as String),
          deletedAt: Value(
            epochMsDariBackendNullable(row['deleted_at'] as String?),
          ),
        ),
      );
    }

    for (final row in hasil.hargaGrosir) {
      await hargaDao.upsertHargaGrosir(
        HargaGrosirCompanion.insert(
          id: row['id'] as String,
          produkId: row['produk_id'] as String,
          varianId: Value(row['varian_id'] as String?),
          outletId: Value(row['outlet_id'] as String?),
          minQty: realDariBackend(row['min_qty'] as String),
          harga: uangDariBackend(row['harga'] as String),
          createdAt: epochMsDariBackend(row['updated_at'] as String),
          updatedAt: epochMsDariBackend(row['updated_at'] as String),
          deletedAt: Value(
            epochMsDariBackendNullable(row['deleted_at'] as String?),
          ),
        ),
      );
    }

    // tipe_order_pajak: relasi murni tanpa updated_at - createdAt lokal
    // diisi waktu pull ini (bukan waktu baris itu sebenarnya dibuat di
    // server, tidak penting krn tabel ini cuma dibaca sbg lookup).
    final waktuPullMs = epochMsDariBackend(hasil.waktuPull);
    for (final row in hasil.tipeOrderPajak) {
      await tipeOrderDao.upsertTipeOrderPajak(
        TipeOrderPajakCompanion.insert(
          tipeOrderId: row['tipe_order_id'] as String,
          pajakId: row['pajak_id'] as String,
          createdAt: waktuPullMs,
        ),
      );
    }

    for (final row in hasil.pengaturanOutlet) {
      await hargaDao.upsertPengaturanOutlet(
        PengaturanOutletCompanion.insert(
          outletId: row['outlet_id'] as String,
          headerStruk: Value(row['header_struk'] as String?),
          footerStruk: Value(row['footer_struk'] as String?),
          tampilLogo: Value(row['tampil_logo'] as bool),
          lebarKertasMm: Value(row['lebar_kertas_mm'] as int),
          pembulatan: Value(row['pembulatan'] as int),
          izinkanStokMinus: Value(row['izinkan_stok_minus'] as bool),
          wajibBukaShift: Value(row['wajib_buka_shift'] as bool),
          strukRingkas: Value(row['struk_ringkas'] as bool),
          pakaiNomorAntrean: Value(row['pakai_nomor_antrean'] as bool),
          antreanAwalan: Value((row['antrean_awalan'] as String?) ?? 'A'),
          antreanMulai: Value((row['antrean_mulai'] as int?) ?? 1),
          estimasiMenit: Value((row['estimasi_menit'] as int?) ?? 0),
          batasMargin: Value((row['batas_margin'] as int?) ?? 50),
          createdAt: epochMsDariBackend(row['updated_at'] as String),
          updatedAt: epochMsDariBackend(row['updated_at'] as String),
          deletedAt: Value(
            epochMsDariBackendNullable(row['deleted_at'] as String?),
          ),
        ),
      );
    }

    // Tahap 5b (desain #2) - "karyawan = baris pengguna server". `id` di
    // sini SELALU id server asli (karyawan cuma bisa dibuat lewat server
    // sejak tahap ini) - jadi serverPenggunaId diisi SAMA dgn id,
    // percobaanGagal/terkunciSampai (kolom LOKAL murni, lockout PIN)
    // SENGAJA tidak disertakan di Companion supaya insertOnConflictUpdate
    // TIDAK menimpanya pada baris yang sudah ada (lihat PenggunaDao).
    for (final row in hasil.role) {
      await penggunaDao.upsertRole(
        RoleCompanion.insert(
          id: row['id'] as String,
          nama: row['nama'] as String,
          isSystem: Value(row['is_system'] as bool),
          createdAt: epochMsDariBackend(row['updated_at'] as String),
          updatedAt: epochMsDariBackend(row['updated_at'] as String),
          deletedAt: Value(
            epochMsDariBackendNullable(row['deleted_at'] as String?),
          ),
        ),
      );
    }
    for (final row in hasil.roleIzin) {
      await penggunaDao.upsertRoleIzinSync(
        RoleIzinSyncCompanion.insert(
          roleId: row['role_id'] as String,
          izinKode: row['izin_kode'] as String,
        ),
      );
    }
    // Varian/tambahan produk: grup + opsi di-upsert (delta), relasi produk-grup
    // diganti seluruhnya dengan snapshot server.
    for (final row in hasil.grupModifier) {
      await produkDao.upsertGrupModifier(
        GrupModifierCompanion.insert(
          id: row['id'] as String,
          tokoId: tokoId,
          nama: row['nama'] as String,
          minPilih: Value(row['min_pilih'] as int),
          maksPilih: Value(row['maks_pilih'] as int),
          createdAt: epochMsDariBackend(row['updated_at'] as String),
          updatedAt: epochMsDariBackend(row['updated_at'] as String),
          deletedAt: Value(epochMsDariBackendNullable(row['deleted_at'] as String?)),
        ),
      );
    }
    for (final row in hasil.modifier) {
      await produkDao.upsertModifier(
        ModifierCompanion.insert(
          id: row['id'] as String,
          grupModifierId: row['grup_modifier_id'] as String,
          nama: row['nama'] as String,
          hargaTambahan: Value(uangDariBackend(row['harga_tambahan'] as String)),
          urutan: Value(row['urutan'] as int),
          aktif: Value(row['aktif'] as bool),
          createdAt: epochMsDariBackend(row['updated_at'] as String),
          updatedAt: epochMsDariBackend(row['updated_at'] as String),
          deletedAt: Value(epochMsDariBackendNullable(row['deleted_at'] as String?)),
        ),
      );
    }
    await produkDao.gantiRelasiProdukGrup([
      for (final row in hasil.produkGrupModifier) (row['produk_id'] as String, row['grup_modifier_id'] as String),
    ]);

    for (final row in hasil.pengguna) {
      await penggunaDao.upsertPenggunaDariSync(
        PenggunaCompanion.insert(
          id: row['id'] as String,
          tokoId: tokoId,
          roleId: row['role_id'] as String,
          nama: row['nama'] as String,
          noHp: Value(row['no_hp'] as String?),
          pinHash: Value(row['pin_hash'] as String?),
          aktif: Value(row['aktif'] as bool),
          serverPenggunaId: Value(row['id'] as String),
          createdAt: epochMsDariBackend(row['updated_at'] as String),
          updatedAt: epochMsDariBackend(row['updated_at'] as String),
          deletedAt: Value(
            epochMsDariBackendNullable(row['deleted_at'] as String?),
          ),
        ),
      );
    }
  }

  ProdukTipe _produkTipeEnum(String backendValue) =>
      ProdukTipe.values.byName(produkTipeDariBackend(backendValue));

  PajakTipe _pajakTipeEnum(String backendValue) =>
      PajakTipe.values.byName(backendValue);

  PromoTipe _promoTipeEnum(String backendValue) =>
      PromoTipe.values.byName(backendValue);

  MetodeBayarTipe _metodeBayarTipeEnum(String backendValue) =>
      MetodeBayarTipe.values.byName(backendValue);
}

final syncRepositoryProvider = Provider<SyncRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return SyncRepository(
    api: ref.watch(backendApiProvider),
    sessionStore: ref.watch(authSessionStoreProvider),
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
    metodeBayarTunaiFallback: ref.watch(metodeBayarTunaiIdProvider),
    baseUrl: ref.watch(baseUrlProvider),
  );
});
