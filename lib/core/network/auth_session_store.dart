import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../providers/device_pairing_provider.dart';
import '../providers/session_provider.dart';

/// Hasil pairing OTP yang perlu diingat lintas-restart app: token
/// akses/refresh + id ASLI dari backend (toko/outlet/pengguna/perangkat).
/// Disimpan di secure storage yang sama dengan `devicePairedProvider` -
/// AuthGatePage baca ini sekali saat app start utk "bootstrap" provider
/// sesi (session_provider.dart) sebelum menampilkan layar manapun, supaya
/// pengguna yang kembali (device sudah pernah pairing) tetap dapat id
/// sungguhan, bukan placeholder.
class SesiBackend {
  const SesiBackend({
    required this.accessToken,
    required this.refreshToken,
    required this.tokoId,
    required this.outletId,
    required this.penggunaId,
    required this.perangkatId,
  });

  final String accessToken;
  final String refreshToken;
  final String tokoId;
  final String outletId;
  final String penggunaId;
  final String perangkatId;
}

const _kAccessTokenKey = 'backend_access_token';
const _kRefreshTokenKey = 'backend_refresh_token';
const _kTokoIdKey = 'backend_toko_id';
const _kOutletIdKey = 'backend_outlet_id';
const _kPenggunaIdKey = 'backend_pengguna_id';
const _kPerangkatIdKey = 'backend_perangkat_id';
const _kLastSyncAtKey = 'backend_last_sync_at';

class AuthSessionStore {
  AuthSessionStore(this._storage);

  final FlutterSecureStorage _storage;

  Future<void> simpan(SesiBackend sesi) async {
    await _storage.write(key: _kAccessTokenKey, value: sesi.accessToken);
    await _storage.write(key: _kRefreshTokenKey, value: sesi.refreshToken);
    await _storage.write(key: _kTokoIdKey, value: sesi.tokoId);
    await _storage.write(key: _kOutletIdKey, value: sesi.outletId);
    await _storage.write(key: _kPenggunaIdKey, value: sesi.penggunaId);
    await _storage.write(key: _kPerangkatIdKey, value: sesi.perangkatId);
  }

  Future<void> simpanAccessToken(String accessToken) async {
    await _storage.write(key: _kAccessTokenKey, value: accessToken);
  }

  Future<SesiBackend?> muat() async {
    final access = await _storage.read(key: _kAccessTokenKey);
    final refresh = await _storage.read(key: _kRefreshTokenKey);
    final tokoId = await _storage.read(key: _kTokoIdKey);
    final outletId = await _storage.read(key: _kOutletIdKey);
    final penggunaId = await _storage.read(key: _kPenggunaIdKey);
    final perangkatId = await _storage.read(key: _kPerangkatIdKey);
    if (access == null ||
        refresh == null ||
        tokoId == null ||
        outletId == null ||
        penggunaId == null ||
        perangkatId == null) {
      return null;
    }
    return SesiBackend(
      accessToken: access,
      refreshToken: refresh,
      tokoId: tokoId,
      outletId: outletId,
      penggunaId: penggunaId,
      perangkatId: perangkatId,
    );
  }

  Future<String?> ambilRefreshToken() => _storage.read(key: _kRefreshTokenKey);

  /// Watermark pull-sync terakhir (ISO8601) - lihat SyncRepository.pull().
  /// Default epoch 0 kalau belum pernah sync sama sekali (sesuai dokumen
  /// kontrak `/sync/pull`: "kosongkan sync pertama kali dgn epoch 0").
  Future<String> ambilLastSyncAt() async =>
      await _storage.read(key: _kLastSyncAtKey) ?? DateTime.utc(1970).toIso8601String();

  Future<void> simpanLastSyncAt(String iso8601) async {
    await _storage.write(key: _kLastSyncAtKey, value: iso8601);
  }
}

final authSessionStoreProvider = Provider<AuthSessionStore>((ref) {
  return AuthSessionStore(ref.watch(secureStorageProvider));
});

/// Dipanggil sekali dari AuthGatePage sebelum menampilkan LoginPage -
/// kalau device sudah pernah pairing (lihat devicePairedProvider), muat
/// kembali id toko/outlet/perangkat ASLI hasil pairing dari secure storage
/// ke provider sesi in-memory (session_provider.dart) yang defaultnya
/// placeholder. TANPA ini, setelah app di-restart, kasir akan memakai id
/// placeholder lagi walau device sudah paired - sync push/pull jadi salah
/// toko_id.
final authBootstrapProvider = FutureProvider<void>((ref) async {
  final paired = await ref.watch(devicePairedProvider.future);
  if (!paired) return;

  final sesi = await ref.watch(authSessionStoreProvider).muat();
  if (sesi == null) return;

  ref.read(currentTokoIdProvider.notifier).set(sesi.tokoId);
  ref.read(currentOutletIdProvider.notifier).set(sesi.outletId);
  ref.read(currentPerangkatIdProvider.notifier).set(sesi.perangkatId);
});
