import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../utils/id_generator.dart';

const _kDevicePairedKey = 'device_paired';
const _kDeviceUidKey = 'device_uid';

final secureStorageProvider = Provider<FlutterSecureStorage>((ref) {
  return const FlutterSecureStorage();
});

/// Sudah pernah verifikasi OTP di HP ini (lewat /auth/otp/verify
/// sungguhan - lihat otp_login_page.dart + AuthSessionStore) ATAU pernah
/// pilih "Masuk dengan PIN karyawan" (skip pairing)? Dicek sekali saat app
/// start - kalau sudah, AuthGatePage langsung ke pilih-pengguna+PIN
/// (lihat LoginPage), tidak tampil OtpLoginPage lagi tiap buka app.
final devicePairedProvider = FutureProvider<bool>((ref) async {
  final storage = ref.watch(secureStorageProvider);
  final value = await storage.read(key: _kDevicePairedKey);
  return value == 'true';
});

Future<void> tandaiDeviceSudahPaired(WidgetRef ref) async {
  final storage = ref.read(secureStorageProvider);
  await storage.write(key: _kDevicePairedKey, value: 'true');
  ref.invalidate(devicePairedProvider);
}

/// Id perangkat yang dikirim ke backend sbg `device_uid` saat pairing -
/// dibuat sekali lalu disimpan permanen di secure storage (BUKAN device
/// fingerprint sungguhan spt IMEI/Android ID - tidak ada package
/// device_info_plus di project ini - cukup utk membedakan device secara
/// konsisten antar sesi app yang sama).
Future<String> ambilDeviceUid(WidgetRef ref) async {
  final storage = ref.read(secureStorageProvider);
  final existing = await storage.read(key: _kDeviceUidKey);
  if (existing != null) return existing;
  final baru = generateId();
  await storage.write(key: _kDeviceUidKey, value: baru);
  return baru;
}
