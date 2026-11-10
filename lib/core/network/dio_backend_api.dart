import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_config.dart';
import 'auth_session_store.dart';
import 'backend_api.dart';
import 'backend_exception.dart';
import 'fitur_terkunci_event.dart' show fiturTerkunciEventProvider;
import 'nama_fitur.dart';

class DioBackendApi implements BackendApi {
  /// [dio] opsional, murni utk testability (lihat
  /// test/dio_backend_api_refresh_test.dart) - supaya test bisa pasang
  /// HttpClientAdapter palsu dan tetap mendapat interceptor
  /// refresh-token/fitur-terkunci yang sama persis dgn produksi. Produksi
  /// SELALU lewat jalur default (null -> bikin Dio baru).
  DioBackendApi(
    String baseUrl, {
    void Function(String fitur, String? paketMinimal)? onFiturTerkunci,
    AuthSessionStore? sessionStore,
    Dio? dio,
  }) : _dio = dio ??
           Dio(
             BaseOptions(
               baseUrl: baseUrl,
               connectTimeout: const Duration(seconds: 10),
               receiveTimeout: const Duration(seconds: 15),
             ),
           ) {
    if (onFiturTerkunci != null) {
      _dio.interceptors.add(
        InterceptorsWrapper(
          onError: (e, handler) {
            // Server menolak 403 `{"detail": {"kode": "fitur_terkunci", ...}}`
            // (lihat backend/app/services/fitur_service.py::tolak_fitur_terkunci)
            // - cache lokal (FeatureGate) bisa basi (belum sync sejak
            // upgrade/downgrade paket), jadi INI yang jadi sumber kebenaran
            // akhir utk nunjukin bottom sheet "Tersedia di paket X", bukan
            // cuma gate di sisi Flutter.
            final data = e.response?.data;
            if (e.response?.statusCode == 403 &&
                data is Map &&
                data['detail'] is Map) {
              final detail = data['detail'] as Map;
              if (detail['kode'] == 'fitur_terkunci') {
                onFiturTerkunci(
                  detail['fitur'] as String,
                  detail['paket_minimal'] as String?,
                );
              }
            }
            handler.next(e);
          },
        ),
      );
    }

    // Bug nyata (laporan pengguna: "token tidak valid: signature has
    // expired" muncul di hampir semua aksi online) - access token cuma
    // berlaku 30 menit (lihat backend Settings.access_token_expire_minutes),
    // dan `refreshAccessToken()` di bawah SEBELUM INI tidak pernah
    // dipanggil dari mana pun - begitu lewat 30 menit, SEMUA request
    // online gagal permanen sampai device di-pairing ulang. Interceptor
    // ini otomatis minta token baru pakai refresh token (umurnya 30 HARI,
    // lihat Settings.refresh_token_expire_days) sekali tiap ada 401, lalu
    // mengulang request yang gagal - transparan, pemanggil tidak perlu
    // tahu soal ini sama sekali.
    if (sessionStore != null) {
      _dio.interceptors.add(
        InterceptorsWrapper(
          onError: (e, handler) async {
            final sudahDicoba = e.requestOptions.extra['_sudahCobaRefreshToken'] == true;
            final jalurRefreshSendiri = e.requestOptions.path.contains('/auth/refresh');
            if (e.response?.statusCode != 401 || sudahDicoba || jalurRefreshSendiri) {
              handler.next(e);
              return;
            }
            final refreshToken = await sessionStore.ambilRefreshToken();
            if (refreshToken == null) {
              handler.next(e);
              return;
            }
            try {
              final respRefresh = await _dio.post(
                '/auth/refresh',
                data: {'refresh_token': refreshToken},
                options: Options(extra: {'_sudahCobaRefreshToken': true}),
              );
              final accessBaru = respRefresh.data['access_token'] as String;
              await sessionStore.simpanAccessToken(accessBaru);

              final opsiUlang = e.requestOptions;
              opsiUlang.headers['Authorization'] = 'Bearer $accessBaru';
              opsiUlang.extra['_sudahCobaRefreshToken'] = true;
              final respUlang = await _dio.fetch<dynamic>(opsiUlang);
              handler.resolve(respUlang);
            } catch (_) {
              // Refresh token-nya sendiri sudah tidak valid/kedaluwarsa
              // (umur 30 hari) - tidak ada yang bisa dipulihkan otomatis,
              // teruskan error 401 ASLI apa adanya spy pemanggil tahu
              // harus pairing ulang, bukan error refresh yang membingungkan.
              handler.next(e);
            }
          },
        ),
      );
    }
  }

  final Dio _dio;

  Never _lempar(DioException e) {
    final status = e.response?.statusCode;
    final data = e.response?.data;
    String pesan;
    final detail = data is Map ? data['detail'] : null;
    if (detail is String) {
      pesan = detail;
    } else if (detail is Map) {
      // Bug nyata (ditemukan dari laporan "error mentah" di layar Edit
      // Produk): dulu `detail.toString()` dibuang apa adanya ke UI -
      // backend kirim body terstruktur `{"kode": ..., ...}` (lihat
      // app/services/fitur_service.py, checkout_service.py dkk), hasilnya
      // teks Dart Map mentah spt "{kode: fitur_terkunci, fitur: resep,
      // paket_minimal: Pro}" nyasar ke layar. Terjemahkan kode yang
      // dikenal jadi kalimat manusiawi; `pesan` eksplisit dari backend
      // (kalau ada) dipakai langsung; selain itu baru fallback ke kode.
      pesan = _pesanDariDetail(detail) ?? detail['pesan']?.toString() ?? 'Terjadi kesalahan (${detail['kode']})';
    } else if (status == null) {
      pesan = 'Tidak bisa menghubungi server - periksa koneksi internet';
    } else {
      pesan = 'Server membalas error ($status)';
    }
    throw BackendException(message: pesan, statusCode: status);
  }

  String? _pesanDariDetail(Map detail) {
    switch (detail['kode']) {
      case 'fitur_terkunci':
        final fitur = namaTampilanFitur(detail['fitur']?.toString() ?? '');
        final paket = detail['paket_minimal'];
        return paket != null
            ? 'Fitur "$fitur" tersedia mulai paket $paket'
            : 'Fitur "$fitur" belum tersedia di paket toko ini';
      case 'kuota_habis':
        final jenis = detail['jenis'];
        final batas = detail['batas'];
        return 'Kuota $jenis sudah penuh (maks $batas) - upgrade paket utk menambah kuota';
      default:
        return null;
    }
  }

  @override
  Future<OtpRequestResult> otpRequest({required String noHp}) async {
    try {
      final resp = await _dio.post('/auth/otp/request', data: {'no_hp': noHp});
      return OtpRequestResult(expiresIn: resp.data['expires_in'] as int);
    } on DioException catch (e) {
      _lempar(e);
    }
  }

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
  }) async {
    try {
      final resp = await _dio.post(
        '/auth/otp/verify',
        data: {
          'no_hp': noHp,
          'kode': kode,
          'device_uid': deviceUid,
          'nama_perangkat': namaPerangkat,
          if (platform != null) 'platform': platform,
          if (namaToko != null) 'nama_toko': namaToko,
          if (jenisUsaha != null) 'jenis_usaha': jenisUsaha,
          if (namaPemilik != null) 'nama_pemilik': namaPemilik,
          if (pin != null) 'pin': pin,
        },
      );
      final body = resp.data as Map<String, dynamic>;
      final toko = body['toko'] as Map<String, dynamic>;
      final outlet = body['outlet'] as Map<String, dynamic>;
      final pengguna = body['pengguna'] as Map<String, dynamic>;
      return AuthResult(
        accessToken: body['access_token'] as String,
        refreshToken: body['refresh_token'] as String,
        tokoId: toko['id'] as String,
        tokoNama: toko['nama'] as String,
        outletId: outlet['id'] as String,
        outletNama: outlet['nama'] as String,
        outletKode: outlet['kode'] as String,
        penggunaId: pengguna['id'] as String,
        penggunaNama: pengguna['nama'] as String,
        perangkatId: body['perangkat_id'] as String,
      );
    } on DioException catch (e) {
      _lempar(e);
    }
  }

  @override
  Future<String> refreshAccessToken({required String refreshToken}) async {
    try {
      final resp = await _dio.post(
        '/auth/refresh',
        data: {'refresh_token': refreshToken},
      );
      return resp.data['access_token'] as String;
    } on DioException catch (e) {
      _lempar(e);
    }
  }

  @override
  Future<PinLoginResult> pinLoginOnline({
    required String perangkatId,
    required String penggunaId,
    required String pin,
  }) async {
    try {
      final resp = await _dio.post(
        '/auth/pin-login',
        data: {'perangkat_id': perangkatId, 'pengguna_id': penggunaId, 'pin': pin},
      );
      final body = resp.data as Map<String, dynamic>;
      return PinLoginResult(
        accessToken: body['access_token'] as String,
        refreshToken: body['refresh_token'] as String,
        penggunaId: (body['pengguna'] as Map<String, dynamic>)['id'] as String,
      );
    } on DioException catch (e) {
      _lempar(e);
    }
  }

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
    try {
      final resp = await _dio.post(
        '/sync/push',
        data: {
          'perangkat_id': perangkatId,
          'transaksi': transaksi,
          'shift': shift,
          'kas_shift': kasShift,
          'pembayaran': pembayaran,
          'pesanan_batal': pesananBatal,
          'status_pesanan': statusPesanan,
        },
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      final body = resp.data as Map<String, dynamic>;
      List<HasilPushItem> hasilUntuk(String key) =>
          ((body[key] as List?) ?? const [])
              .map(
                (e) => HasilPushItem(
                  id: e['id'] as String,
                  status: e['status'] as String,
                  pesan: e['pesan'] as String?,
                ),
              )
              .toList();
      return SyncPushResult(
        transaksi: hasilUntuk('transaksi'),
        pembayaran: hasilUntuk('pembayaran'),
        pesananBatal: hasilUntuk('pesanan_batal'),
        statusPesanan: hasilUntuk('status_pesanan'),
      );
    } on DioException catch (e) {
      _lempar(e);
    }
  }

  @override
  Future<SyncPullResult> syncPull({
    required String accessToken,
    required String perangkatId,
    required String since,
    String? outletId,
    int limit = 500,
  }) async {
    try {
      final resp = await _dio.get(
        '/sync/pull',
        queryParameters: {
          'perangkat_id': perangkatId,
          'since': since,
          'limit': limit,
          if (outletId != null) 'outlet_id': outletId,
        },
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      final body = resp.data as Map<String, dynamic>;
      List<Map<String, dynamic>> listOf(String key) =>
          ((body[key] as List?) ?? const []).cast<Map<String, dynamic>>();
      return SyncPullResult(
        waktuPull: body['waktu_pull'] as String,
        produk: listOf('produk'),
        kategori: listOf('kategori'),
        satuan: listOf('satuan'),
        pajak: listOf('pajak'),
        promo: listOf('promo'),
        metodeBayar: listOf('metode_bayar'),
        stok: listOf('stok'),
        hargaOutlet: listOf('harga_outlet'),
        hargaGrosir: listOf('harga_grosir'),
        tipeOrderPajak: listOf('tipe_order_pajak'),
        pengaturanOutlet: listOf('pengaturan_outlet'),
        hasMore: (body['has_more'] as Map<String, dynamic>).map(
          (k, v) => MapEntry(k, v as bool),
        ),
        paket: body['paket'] as String?,
        logoUrl: body['logo_url'] as String?,
        kodeFitur: (body['kode_fitur'] as List).cast<String>(),
        batasFitur: (body['batas_fitur'] as Map<String, dynamic>).map(
          (k, v) => MapEntry(k, v as int),
        ),
        pengguna: listOf('pengguna'),
        role: listOf('role'),
        roleIzin: listOf('role_izin'),
        pelanggan: listOf('pelanggan'),
        grupModifier: listOf('grup_modifier'),
        modifier: listOf('modifier'),
        produkGrupModifier: listOf('produk_grup_modifier'),
      );
    } on DioException catch (e) {
      _lempar(e);
    }
  }

  @override
  Future<Map<String, dynamic>> ambilPengaturanOutlet({
    required String accessToken,
    required String outletId,
  }) async {
    try {
      final resp = await _dio.get(
        '/outlets/$outletId/pengaturan',
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      return resp.data as Map<String, dynamic>;
    } on DioException catch (e) {
      _lempar(e);
    }
  }

  @override
  Future<Map<String, dynamic>> ubahPengaturanOutlet({
    required String accessToken,
    required String outletId,
    required Map<String, dynamic> body,
  }) async {
    try {
      final resp = await _dio.patch(
        '/outlets/$outletId/pengaturan',
        data: body,
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      return resp.data as Map<String, dynamic>;
    } on DioException catch (e) {
      _lempar(e);
    }
  }

  @override
  Future<String> uploadLogoToko({
    required String accessToken,
    required List<int> bytes,
    required String namaFile,
  }) async {
    try {
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(bytes, filename: namaFile),
      });
      final resp = await _dio.post(
        '/toko/logo',
        data: formData,
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      final body = resp.data as Map<String, dynamic>;
      return body['logo_url'] as String;
    } on DioException catch (e) {
      _lempar(e);
    }
  }

  @override
  Future<Map<String, dynamic>> ubahMetodeBayar({
    required String accessToken,
    required String metodeBayarId,
    required Map<String, dynamic> body,
  }) async {
    try {
      final resp = await _dio.patch(
        '/metode-bayar/$metodeBayarId',
        data: body,
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      return resp.data as Map<String, dynamic>;
    } on DioException catch (e) {
      _lempar(e);
    }
  }

  @override
  Future<Map<String, dynamic>> ambilTransaksi({
    required String accessToken,
    required String outletId,
    required String dariTanggal,
    required String sampaiTanggal,
    int limit = 200,
    int offset = 0,
  }) async {
    try {
      final resp = await _dio.get(
        '/transaksi',
        queryParameters: {
          'outlet_id': outletId,
          'dari_tanggal': dariTanggal,
          'sampai_tanggal': sampaiTanggal,
          'limit': limit,
          'offset': offset,
        },
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      return resp.data as Map<String, dynamic>;
    } on DioException catch (e) {
      _lempar(e);
    }
  }

  @override
  Future<Map<String, dynamic>> ambilDetailTransaksi({
    required String accessToken,
    required String transaksiId,
  }) async {
    try {
      final resp = await _dio.get(
        '/transaksi/$transaksiId',
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      return resp.data as Map<String, dynamic>;
    } on DioException catch (e) {
      _lempar(e);
    }
  }

  @override
  Future<List<Map<String, dynamic>>> ambilItemRefundable({
    required String accessToken,
    required String transaksiId,
  }) async {
    try {
      final resp = await _dio.get(
        '/transaksi/$transaksiId/item-refundable',
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      return (resp.data as List).cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      _lempar(e);
    }
  }

  @override
  Future<Map<String, dynamic>> buatRefund({
    required String accessToken,
    required String transaksiId,
    required Map<String, dynamic> body,
  }) async {
    try {
      final resp = await _dio.post(
        '/transaksi/$transaksiId/refund',
        data: body,
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      return resp.data as Map<String, dynamic>;
    } on DioException catch (e) {
      _lempar(e);
    }
  }

  @override
  Future<List<Map<String, dynamic>>> ambilDaftarPaket({required String accessToken}) async {
    try {
      final resp = await _dio.get(
        '/paket',
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      return (resp.data as List).cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      _lempar(e);
    }
  }

  @override
  Future<Map<String, dynamic>> ambilLanggananSaya({required String accessToken}) async {
    try {
      final resp = await _dio.get(
        '/langganan/saya',
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      return resp.data as Map<String, dynamic>;
    } on DioException catch (e) {
      _lempar(e);
    }
  }

  @override
  Future<Map<String, dynamic>> ajukanUpgrade({
    required String accessToken,
    required Map<String, dynamic> body,
  }) async {
    try {
      final resp = await _dio.post(
        '/langganan/permintaan-upgrade',
        data: body,
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      return resp.data as Map<String, dynamic>;
    } on DioException catch (e) {
      _lempar(e);
    }
  }

  @override
  Future<Map<String, dynamic>> checkoutUpgrade({
    required String accessToken,
    required Map<String, dynamic> body,
  }) async {
    try {
      final resp = await _dio.post(
        '/langganan/checkout-upgrade',
        data: body,
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      return resp.data as Map<String, dynamic>;
    } on DioException catch (e) {
      _lempar(e);
    }
  }

  @override
  Future<Map<String, dynamic>> statusCheckoutUpgrade({
    required String accessToken,
    required String permintaanId,
  }) async {
    try {
      final resp = await _dio.get(
        '/langganan/checkout-upgrade/$permintaanId/status',
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      return resp.data as Map<String, dynamic>;
    } on DioException catch (e) {
      _lempar(e);
    }
  }

  @override
  Future<void> batalkanPesananTersimpan({
    required String accessToken,
    required String pesananId,
    required Map<String, dynamic> body,
  }) async {
    try {
      await _dio.post(
        '/transaksi/pesanan-tersimpan/$pesananId/batalkan',
        data: body,
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
    } on DioException catch (e) {
      _lempar(e);
    }
  }

  @override
  Future<dynamic> getJson({
    required String accessToken,
    required String path,
    Map<String, dynamic>? query,
  }) async {
    try {
      final resp = await _dio.get(
        path,
        queryParameters: query,
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      return resp.data;
    } on DioException catch (e) {
      _lempar(e);
    }
  }

  @override
  Future<dynamic> postJson({
    required String accessToken,
    required String path,
    Map<String, dynamic>? body,
  }) async {
    try {
      final resp = await _dio.post(
        path,
        data: body,
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      return resp.data;
    } on DioException catch (e) {
      _lempar(e);
    }
  }

  @override
  Future<dynamic> patchJson({
    required String accessToken,
    required String path,
    required Map<String, dynamic> body,
  }) async {
    try {
      final resp = await _dio.patch(
        path,
        data: body,
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      return resp.data;
    } on DioException catch (e) {
      _lempar(e);
    }
  }

  @override
  Future<void> deleteJson({required String accessToken, required String path}) async {
    try {
      await _dio.delete(
        path,
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
    } on DioException catch (e) {
      _lempar(e);
    }
  }

  @override
  Future<dynamic> putJsonBody({
    required String accessToken,
    required String path,
    required Map<String, dynamic> body,
  }) async {
    try {
      final resp = await _dio.put(
        path,
        data: body,
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      return resp.data;
    } on DioException catch (e) {
      _lempar(e);
    }
  }

  @override
  Future<void> putJsonIds({
    required String accessToken,
    required String path,
    required List<String> ids,
  }) async {
    try {
      await _dio.put(
        path,
        data: {'ids': ids},
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
    } on DioException catch (e) {
      _lempar(e);
    }
  }
}

final backendApiProvider = Provider<BackendApi>((ref) {
  return DioBackendApi(
    ref.watch(baseUrlProvider),
    onFiturTerkunci: (fitur, paketMinimal) => ref
        .read(fiturTerkunciEventProvider.notifier)
        .tampilkan(fitur, paketMinimal),
    sessionStore: ref.watch(authSessionStoreProvider),
  );
});
