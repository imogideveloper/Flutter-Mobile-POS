import 'dart:convert';
import 'dart:typed_data';

import 'package:apps_pos/core/network/auth_session_store.dart';
import 'package:apps_pos/core/network/dio_backend_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pengganti request HTTP sungguhan - balas 401 utk path tertentu PERSIS
/// SEKALI (simulasi token akses kedaluwarsa), lalu 200 utk percobaan
/// berikutnya (simulasi berhasil setelah token baru dipakai). Juga catat
/// semua header Authorization yang dipakai supaya test bisa pastikan
/// token BARU yang terpakai saat mengulang, bukan token lama yang sudah
/// kedaluwarsa.
class _FakeHttpClientAdapter implements HttpClientAdapter {
  final List<String> pathDipanggil = [];
  final List<String?> authHeaderDipakai = [];
  bool sudahPernah401 = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    pathDipanggil.add(options.path);
    authHeaderDipakai.add(options.headers['Authorization'] as String?);

    if (options.path == '/auth/refresh') {
      return _responJson(200, {'access_token': 'token-baru'});
    }

    if (options.path == '/protected' && !sudahPernah401) {
      sudahPernah401 = true;
      return _responJson(401, {'detail': 'Signature has expired'});
    }

    return _responJson(200, {'ok': true});
  }

  ResponseBody _responJson(int statusCode, Map<String, dynamic> data) {
    final bytes = utf8.encode(jsonEncode(data));
    return ResponseBody(
      Stream.value(Uint8List.fromList(bytes)),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _FakeAuthSessionStoreDenganRefresh extends AuthSessionStore {
  _FakeAuthSessionStoreDenganRefresh() : super(const FlutterSecureStorage());

  String? accessTokenTersimpan;

  @override
  Future<String?> ambilRefreshToken() async => 'refresh-token-lama';

  @override
  Future<void> simpanAccessToken(String accessToken) async {
    accessTokenTersimpan = accessToken;
  }
}

/// Regresi utk bug nyata yang dilaporkan pengguna: "token tidak valid:
/// signature has expired" muncul terus-menerus di hampir semua aksi
/// online setelah device dipakai > 30 menit. Akar masalah:
/// refreshAccessToken() ADA tapi TIDAK PERNAH dipanggil dari mana pun -
/// begitu access token (umur 30 menit) kedaluwarsa, semua request online
/// gagal permanen sampai pairing ulang. Interceptor baru di
/// DioBackendApi sekarang otomatis minta token baru & mengulang request
/// yang gagal - lihat catatan lengkap di dio_backend_api.dart.
void main() {
  test('401 pada request terautentikasi otomatis refresh token lalu mengulang request', () async {
    final adapter = _FakeHttpClientAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://api.test'))..httpClientAdapter = adapter;
    final sessionStore = _FakeAuthSessionStoreDenganRefresh();
    final api = DioBackendApi('https://api.test', sessionStore: sessionStore, dio: dio);

    final hasil = await api.getJson(accessToken: 'token-lama-kedaluwarsa', path: '/protected');

    expect(hasil, {'ok': true});
    // Refresh token-nya benar2 dipakai, dan hasilnya disimpan ke session
    // store - bukan cuma dipakai sekali lalu dibuang.
    expect(sessionStore.accessTokenTersimpan, 'token-baru');
    // Urutan panggilan: /protected (401) -> /auth/refresh -> /protected
    // lagi (kali ini pakai token baru).
    expect(adapter.pathDipanggil, ['/protected', '/auth/refresh', '/protected']);
    expect(adapter.authHeaderDipakai[0], 'Bearer token-lama-kedaluwarsa');
    expect(adapter.authHeaderDipakai[2], 'Bearer token-baru');
  });

  test('refresh token yang juga kedaluwarsa - error 401 ASLI diteruskan apa adanya', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.test'));
    final sessionStore = _FakeAuthSessionStoreDenganRefresh();
    // Adapter baru yang BALAS 401 juga utk /auth/refresh sendiri.
    dio.httpClientAdapter = _SelaluTolakAdapter();
    final api = DioBackendApi('https://api.test', sessionStore: sessionStore, dio: dio);

    await expectLater(
      api.getJson(accessToken: 'token-lama', path: '/protected'),
      throwsA(isA<Exception>()),
    );
    // Tidak pernah "berhasil diam2" dgn token lama yang salah.
    expect(sessionStore.accessTokenTersimpan, isNull);
  });
}

class _SelaluTolakAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final bytes = utf8.encode(jsonEncode({'detail': 'Refresh token tidak valid'}));
    return ResponseBody(
      Stream.value(Uint8List.fromList(bytes)),
      401,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
