import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/dio_backend_api.dart';
import '../../domain/admin_data.dart';

/// Sesi Administrator - SENGAJA hanya di memori (tidak disimpan di perangkat):
/// tutup aplikasi = login admin lagi. Terpisah total dari sesi kasir/toko.
class AdminSesi {
  const AdminSesi({required this.token, required this.nama, required this.email});

  final String token;
  final String nama;
  final String email;
}

class AdminSesiNotifier extends Notifier<AdminSesi?> {
  @override
  AdminSesi? build() => null;

  /// Login email+password ke `/admin/auth/login`. Melempar [BackendException] bila ditolak.
  Future<void> masuk({required String email, required String password}) async {
    final api = ref.read(backendApiProvider);
    final hasil = await api.postJson(
      accessToken: '',
      path: '/admin/auth/login',
      body: {'email': email.trim(), 'password': password},
    ) as Map<String, dynamic>;
    final token = hasil['access_token'] as String;
    final saya = await api.getJson(accessToken: token, path: '/admin/auth/saya') as Map<String, dynamic>;
    state = AdminSesi(token: token, nama: saya['nama'] as String, email: saya['email'] as String);
  }

  void keluar() => state = null;
}

final adminSesiProvider = NotifierProvider<AdminSesiNotifier, AdminSesi?>(AdminSesiNotifier.new);

/// Filter jenis usaha F&B (kode 3 huruf: CAF, RES, CAT, BRD, FRZ, BEV, STL); null = semua.
class JenisUsahaFilterNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void pilih(String? kode) => state = kode;
}

final adminJenisUsahaFilterProvider = NotifierProvider<JenisUsahaFilterNotifier, String?>(JenisUsahaFilterNotifier.new);

/// Pencarian nama usaha di tab Usaha.
class PencarianUsahaNotifier extends Notifier<String> {
  @override
  String build() => '';

  void set(String nilai) => state = nilai;
}

final adminPencarianUsahaProvider = NotifierProvider<PencarianUsahaNotifier, String>(PencarianUsahaNotifier.new);

Future<dynamic> _ambil(Ref ref, String path, {Map<String, dynamic>? query}) {
  final sesi = ref.watch(adminSesiProvider);
  if (sesi == null) throw StateError('Belum login administrator');
  final bersih = <String, dynamic>{
    for (final e in (query ?? const <String, dynamic>{}).entries)
      if (e.value != null && e.value != '') e.key: e.value,
  };
  return ref.watch(backendApiProvider).getJson(accessToken: sesi.token, path: path, query: bersih);
}

final adminJenisUsahaPilihanProvider = FutureProvider<List<PilihanJenisUsaha>>((ref) async {
  final data = await _ambil(ref, '/admin/dashboard/jenis-usaha') as List;
  return [for (final e in data) PilihanJenisUsaha.fromJson(e as Map<String, dynamic>)];
});

final adminRingkasanProvider = FutureProvider<RingkasanAdmin>((ref) async {
  final jenis = ref.watch(adminJenisUsahaFilterProvider);
  final data = await _ambil(ref, '/admin/dashboard/ringkasan', query: {'jenis_usaha': jenis});
  return RingkasanAdmin.fromJson(data as Map<String, dynamic>);
});

final adminUsahaProvider = FutureProvider<List<UsahaAdmin>>((ref) async {
  final jenis = ref.watch(adminJenisUsahaFilterProvider);
  final q = ref.watch(adminPencarianUsahaProvider);
  final data = await _ambil(ref, '/admin/dashboard/usaha', query: {'jenis_usaha': jenis, 'q': q.trim()}) as List;
  return [for (final e in data) UsahaAdmin.fromJson(e as Map<String, dynamic>)];
});

final adminFiturProvider = FutureProvider<List<FiturAdmin>>((ref) async {
  final jenis = ref.watch(adminJenisUsahaFilterProvider);
  final data = await _ambil(ref, '/admin/dashboard/fitur', query: {'jenis_usaha': jenis}) as List;
  return [for (final e in data) FiturAdmin.fromJson(e as Map<String, dynamic>)];
});
