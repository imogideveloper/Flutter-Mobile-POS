import 'package:bcrypt/bcrypt.dart';

/// Tahap 5b (desain #3) - PIN WAJIB di-hash dgn hash yang kuat (bcrypt),
/// BUKAN sha256 polos tanpa salt (bug lama - lihat catatan Langkah 0 di
/// percakapan tahap 5b). Format hash bcrypt ($2a$/$2b$) cross-compatible
/// dgn `bcrypt.hashpw` Python di server (core/security.py) - keduanya
/// implementasi algoritma bcrypt standar, bukan skema proprietary.
String hashPin(String pin) => BCrypt.hashpw(pin, BCrypt.gensalt());

/// `hash` null (karyawan belum pernah diberi PIN) selalu gagal verifikasi
/// - BCrypt.checkpw sendiri akan throw kalau hash bukan format bcrypt
/// valid, jadi null dicek lebih dulu.
bool verifyPin(String pin, String? hash) {
  if (hash == null || hash.isEmpty) return false;
  try {
    return BCrypt.checkpw(pin, hash);
  } catch (_) {
    // Hash lama format sha256 (sebelum tahap 5b) atau korup - dianggap
    // tidak cocok, bukan crash. Karyawan lama perlu reset PIN lewat server.
    return false;
  }
}
