import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Toko/outlet/perangkat mulai dari nilai placeholder (instalasi baru,
/// belum pernah pairing ke backend) - begitu pairing OTP sukses
/// (lihat otp_login_page.dart + AuthSessionStore), `.set(idAsli)` dipanggil
/// supaya seluruh ~20+ pemanggil `ref.watch(currentTokoIdProvider)` yang
/// sudah ada otomatis dapat id backend yang sungguhan tanpa perlu diubah
/// satu per satu - makanya provider ini TETAP `Provider<String>`-shaped
/// (dibaca sinkron) walau sekarang di-backing oleh Notifier yang bisa
/// diubah, bukan literal konstan seperti sebelumnya.
const _tokoIdPlaceholder = 'toko-default';
const _outletIdPlaceholder = 'outlet-default';
const _perangkatIdPlaceholder = 'perangkat-default';
// Belum ada pull-sync metode_bayar yang dipakai utk pilih metode bayar di
// UI (baru dipakai di sisi push - lihat sync_repository.dart) - kasir utk
// sekarang cuma mendukung tunai & QRIS (keduanya di-mock, belum ada
// gateway sungguhan), jadi dua id placeholder ini cukup.
const _metodeBayarTunaiIdPlaceholder = 'metode-tunai-default';
const _metodeBayarQrisIdPlaceholder = 'metode-qris-default';

class _IdSessionNotifier extends Notifier<String> {
  _IdSessionNotifier(this._default);

  final String _default;

  @override
  String build() => _default;

  void set(String id) => state = id;
}

final currentTokoIdProvider =
    NotifierProvider<_IdSessionNotifier, String>(() => _IdSessionNotifier(_tokoIdPlaceholder));
final currentOutletIdProvider =
    NotifierProvider<_IdSessionNotifier, String>(() => _IdSessionNotifier(_outletIdPlaceholder));
final currentPerangkatIdProvider =
    NotifierProvider<_IdSessionNotifier, String>(() => _IdSessionNotifier(_perangkatIdPlaceholder));

final metodeBayarTunaiIdProvider = Provider<String>((ref) => _metodeBayarTunaiIdPlaceholder);
final metodeBayarQrisIdProvider = Provider<String>((ref) => _metodeBayarQrisIdPlaceholder);

/// null = belum ada yang login di HP ini. Session ini sengaja cuma di
/// memori (tidak persist) - keluar app = harus pilih akun lagi, mirip
/// kasir "lock screen" antar shift.
class PenggunaSessionNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void login(String penggunaId) => state = penggunaId;
  void logout() => state = null;
}

final currentPenggunaIdProvider =
    NotifierProvider<PenggunaSessionNotifier, String?>(PenggunaSessionNotifier.new);
